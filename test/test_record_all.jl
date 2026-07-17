# Testimonial.jl — Tests for record_all with parallel recording
#
# Verifies that record_all discovers items, records them in parallel,
# and builds a CoverageIndex. Uses MockRunner to avoid subprocess overhead.
#
# See REC-004 through REC-006 in
# openspec/changes/implement-coverage-layer/specs/recording/spec.md

using Testimonial
using Test
using Dates

# ── Helpers ───────────────────────────────────

"""Create a temp directory with @testitem files for testing."""
function create_test_project(dir::String)
    test_dir = joinpath(dir, "test")
    mkpath(test_dir)

    # File with one @testitem
    write(joinpath(test_dir, "foo_test.jl"), """
    @testitem "test_a" begin
        @test 1 == 1
    end
    """)

    # File with multiple @testitems
    write(joinpath(test_dir, "bar_test.jl"), """
    @testitem "test_b" begin
        @test 2 == 2
    end

    @testitem "test_c" begin
        @test 3 == 3
    end
    """)

    return test_dir
end

# ── record_all with MockRunner ─────────────────

@testset "record_all records all discovered items" begin
    mktempdir() do dir
        test_dir = create_test_project(dir)
        runner = MockRunner()

        # Discover items
        items = Testimonial.discover_testitems([test_dir])

        # Record all with MockRunner (force=true to skip cache)
        index = record_all(items, runner; force=true)

        @test index isa CoverageIndex
        @test length(index.items) == 3

        # Verify all item names are present
        names = sort([ic.item.name for (_, ic) in index.items])
        @test names == ["test_a", "test_b", "test_c"]
    end
end

@testset "record_all uses runner for each item" begin
    mktempdir() do dir
        test_dir = create_test_project(dir)
        runner = MockRunner()

        items = Testimonial.discover_testitems([test_dir])
        record_all(items, runner; force=true)

        # MockRunner captures env vars — item names are in TESTIMONIAL_ITEM
        @test haskey(runner.captured_env, "TESTIMONIAL_ITEM")
        @test runner.captured_env["TESTIMONIAL_FILE"] != ""
        @test runner.captured_env["TESTIMONIAL_ITEM"] != ""
    end
end

@testset "record_all returns empty index for empty items" begin
    runner = MockRunner()
    index = record_all(TestItemRef[], runner; force=true)

    @test index isa CoverageIndex
    @test isempty(index.items)
end

@testset "record_all sets git_hash and schema_version" begin
    mktempdir() do dir
        test_dir = create_test_project(dir)
        runner = MockRunner()

        items = Testimonial.discover_testitems([test_dir])
        index = record_all(items, runner; force=true)

        @test index.schema_version == v"0.1.0"
        @test index.git_hash isa String
        @test !isempty(index.git_hash)
        @test index.created_at isa DateTime
    end
end

@testset "record_all records items with correct coverage data" begin
    mktempdir() do dir
        test_dir = create_test_project(dir)
        runner = MockRunner()

        items = Testimonial.discover_testitems([test_dir])
        index = record_all(items, runner; force=true)

        # Each item should have an ItemCoverage with covered and uncovered lines
        for (ref, ic) in index.items
            @test ic isa ItemCoverage
            @test ic.item == ref
            @test ic.covered_lines isa Vector{Int}
            @test ic.uncovered_lines isa Vector{Int}
        end
    end
end

@testset "record_all with incremental skips unchanged items" begin
    mktempdir() do dir
        test_dir = create_test_project(dir)
        runner = MockRunner()

        items = Testimonial.discover_testitems([test_dir])

        # First run: force=true, records everything
        first_index = record_all(items, runner; force=true)
        @test length(first_index.items) == 3

        # Second run: incremental=true, should skip cached items
        # Reset the runner to count new calls
        runner2 = MockRunner()
        second_index = record_all(items, runner2; incremental=true)

        # Should still return 3 items (from cache)
        @test length(second_index.items) == 3

        # MockRunner should NOT have been called for any item (all cached)
        # when incremental=true and files haven't changed
        @test isempty(runner2.captured_cmd)
    end
end