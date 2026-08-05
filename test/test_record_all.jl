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
using Serialization

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

# ── build_index ────────────────────────────────

@testset "build_index loads records from items directory" begin
    mktempdir() do dir
        items_dir = joinpath(dir, "items")
        mkpath(items_dir)

        # Create serialized ItemCoverage records
        ref1 = TestItemRef("/proj/test/foo_test.jl", 10, "test_a", Symbol[], "abc123")
        ref2 = TestItemRef("/proj/test/bar_test.jl", 5, "test_b", Symbol[], "def456")

        ic1 = ItemCoverage(ref1, [1, 2, 3], [4, 5], Dict())
        ic2 = ItemCoverage(ref2, [10, 11, 12], [13], Dict())

        open(joinpath(items_dir, "abc123-test_a.jls"), "w") do io
            serialize(io, ic1)
        end
        open(joinpath(items_dir, "def456-test_b.jls"), "w") do io
            serialize(io, ic2)
        end

        index = build_index(items_dir)

        @test index isa CoverageIndex
        @test length(index.items) == 2

        # Verify items are loaded correctly
        names = sort([ic.item.name for (_, ic) in index.items])
        @test names == ["test_a", "test_b"]
    end
end

@testset "build_index returns empty index for empty directory" begin
    mktempdir() do dir
        items_dir = joinpath(dir, "items")
        mkpath(items_dir)

        index = build_index(items_dir)

        @test index isa CoverageIndex
        @test isempty(index.items)
    end
end

@testset "build_index ignores non-jls files" begin
    mktempdir() do dir
        items_dir = joinpath(dir, "items")
        mkpath(items_dir)

        # Create a valid record
        ref = TestItemRef("/proj/test/foo_test.jl", 10, "test_a", Symbol[], "abc123")
        ic = ItemCoverage(ref, [1, 2], Int[], Dict())
        open(joinpath(items_dir, "abc123-test_a.jls"), "w") do io
            serialize(io, ic)
        end

        # Create a non-jls file that should be ignored
        write(joinpath(items_dir, "readme.txt"), "not a record")

        index = build_index(items_dir)

        @test length(index.items) == 1
        @test first(values(index.items)).item.name == "test_a"
    end
end

# ── Mixed-mode recording ────────────────────────

"""Create a temp directory with both @testitem and file-level items."""
function create_mixed_project(dir::String)
    test_dir = joinpath(dir, "test")
    mkpath(test_dir)

    # File with @testitem (per-item recording)
    write(joinpath(test_dir, "item_test.jl"), """
    @testitem "test_a" begin
        @test 1 == 1
    end

    @testitem "test_b" begin
        @test 2 == 2
    end
    """)

    # File with @testset blocks (file-level recording)
    write(joinpath(test_dir, "set_test.jl"), """
    @testset "outer" begin
        @test 1 == 1
    end

    @testset "nested" begin
        @test 2 == 2
    end
    """)

    # File with no test blocks at all (triggers file-level fallback, line=0)
    write(joinpath(test_dir, "spec_test.jl"), """
    # This file has no test blocks — just simple tests
    @test 1 == 1
    @test 2 == 2
    """)

    return test_dir
end

@testset "record_all dispatches file-level items to record_file" begin
    mktempdir() do dir
        test_dir = create_mixed_project(dir)
        runner = MockRunner()

        # Discover all items — includes @testitem, @testset, and file-level (line=0) items
        items = Testimonial.discover_all_test_blocks([test_dir])

        # Filter to only file-level items (those with line == 0)
        file_items = [item for item in items if item.line == 0]
        @test !isempty(file_items)

        result = record_all(file_items, runner; force=true)

        # MockRunner should have been called with TESTIMONIAL_RUN_ALL (record_file)
        @test haskey(runner.captured_env, "TESTIMONIAL_RUN_ALL")
        @test runner.captured_env["TESTIMONIAL_RUN_ALL"] == "true"
        # Should NOT have TESTIMONIAL_ITEM (that's for record_item)
        @test !haskey(runner.captured_env, "TESTIMONIAL_ITEM")
        @test !haskey(runner.captured_env, "TESTIMONIAL_ITEMS")
    end
end

@testset "record_all dispatches @testitem items to record_item" begin
    mktempdir() do dir
        test_dir = create_mixed_project(dir)
        runner = MockRunner()

        items = Testimonial.discover_all_test_blocks([test_dir])

        # Filter to only @testitem items (those with line > 0 at a @testitem line)
        item_items = [item for item in items if item.line > 0 && Testimonial.Protocol._is_testitem_at_line(item.file, item.line)]
        @test !isempty(item_items)

        record_all(item_items, runner; force=true)

        # MockRunner should have been called with TESTIMONIAL_ITEM (record_item)
        @test haskey(runner.captured_env, "TESTIMONIAL_ITEM")
        @test runner.captured_env["TESTIMONIAL_ITEM"] != ""
        # Should NOT have TESTIMONIAL_RUN_ALL (that's for record_file)
        @test !haskey(runner.captured_env, "TESTIMONIAL_RUN_ALL")
    end
end

@testset "record_all mixed-mode produces valid CoverageIndex" begin
    mktempdir() do dir
        test_dir = create_mixed_project(dir)
        runner = MockRunner()

        items = Testimonial.discover_all_test_blocks([test_dir])

        # Record ALL items (mixed: @testitem + file-level)
        index = record_all(items, runner; force=true)

        @test index isa CoverageIndex

        # Count item types: @testitem items are those with line > 0 whose
        # line actually contains a @testitem; file-level items are line==0
        # or @testset items (both recorded via record_file → line==0 refs)
        item_items = [ic for (ref, ic) in index.items if ref.line > 0]
        file_items = [ic for (ref, ic) in index.items if ref.line == 0]

        @test !isempty(item_items)
        @test !isempty(file_items)

        # Verify total items
        @test length(index.items) == length(item_items) + length(file_items)

        # File-level items should have basename as name
        for (ref, ic) in index.items
            if ref.line == 0
                @test ref.name == basename(ref.file)
            end
        end
    end
end

@testset "build_index sets metadata fields" begin
    mktempdir() do dir
        items_dir = joinpath(dir, "items")
        mkpath(items_dir)

        index = build_index(items_dir)

        @test index.schema_version == v"0.1.0"
        @test index.git_hash isa String
        @test index.created_at isa DateTime
    end
end

@testset "record_all with batch_by_file handles file-level items" begin
    mktempdir() do dir
        test_dir = create_mixed_project(dir)
        runner = MockRunner()

        # Discover all items
        items = Testimonial.discover_all_test_blocks([test_dir])

        # Record with batch_by_file=true — should handle file-level items
        index = record_all(items, runner; force=true, batch_by_file=true)

        @test index isa CoverageIndex

        # Should have both @testitem and file-level items
        item_items = [ic for (ref, ic) in index.items if ref.line > 0]
        file_items = [ic for (ref, ic) in index.items if ref.line == 0]
        @test !isempty(item_items)
        @test !isempty(file_items)

        # MockRunner should have captured both TESTIMONIAL_ITEM (batch) and TESTIMONIAL_RUN_ALL (file-level)
        @test haskey(runner.captured_env, "TESTIMONIAL_RUN_ALL")
        @test haskey(runner.captured_env, "TESTIMONIAL_ITEM") || haskey(runner.captured_env, "TESTIMONIAL_ITEMS")
    end
end

# ── record_all() — no-argument workflow ──────────

@testset "record_all() discovers and persists default index" begin
    mktempdir() do dir
        # Create a minimal Julia project so the driver exits 0
        write(joinpath(dir, "Project.toml"), """
        name = "RecordAllTest"
        uuid = "00000000-0000-0000-0000-000000000003"
        """)
        src_dir = joinpath(dir, "src")
        mkpath(src_dir)
        write(joinpath(src_dir, "RecordAllTest.jl"), """
        module RecordAllTest
        greet() = "hello"
        end
        """)

        # Create a test project with @testitem files
        test_dir = joinpath(dir, "test")
        mkpath(test_dir)
        write(joinpath(test_dir, "foo_test.jl"), """
        @testitem "test_a" begin
            @test 1 == 1
        end
        """)

        # Call record_all() with no arguments, pointing to the temp project
        # Note: the test project must have a Project.toml for the driver
        # to succeed (testimonial-in3s.3 enforces exit 0 validation).
        index = Testimonial.record_all(;
            project_dir=dir,
            test_dirs=[test_dir],
            force=true,
        )

        @test index isa CoverageIndex
        @test length(index.items) == 1

        # Verify the index was persisted
        index_path = joinpath(dir, ".testimonial", "index.jls")
        @test isfile(index_path)

        # Load and verify
        loaded = Testimonial.load_index(index_path)
        @test loaded isa CoverageIndex
        @test length(loaded.items) == 1

        names = sort([ic.item.name for (_, ic) in loaded.items])
        @test names == ["test_a"]
    end
end

# ── Deterministic partial-failure runner ──────

"""A runner that returns ItemCoverage for the first item and nothing for the rest."""
struct PartialFailRunner <: Testimonial.AbstractRunner end

function Testimonial.record_item(runner::PartialFailRunner, ref::Testimonial.TestItemRef)
    # Return ItemCoverage only for the first item, nothing for subsequent items
    if ref.name == "test_a"
        return Testimonial.ItemCoverage(ref, Int[], Int[], Dict())
    end
    return nothing
end

function Testimonial.record_file(runner::PartialFailRunner, test_file::String)
    ref = Testimonial.TestItemRef(test_file, 0, basename(test_file))
    return Testimonial.ItemCoverage(ref, Int[], Int[], Dict())
end

function Testimonial.record_batch(runner::PartialFailRunner, refs::Vector{Testimonial.TestItemRef})
    return [Testimonial.record_item(runner, r) for r in refs]
end

@testset "record_all reports failed_item_count and total_discovered_items" begin
    mktempdir() do dir
        mkpath(joinpath(dir, "test"))
        mkpath(joinpath(dir, "src"))

        # Two test files
        write(joinpath(dir, "test", "a_test.jl"), """
        @testitem "test_a" begin
            @test 1 == 1
        end
        """)
        write(joinpath(dir, "test", "b_test.jl"), """
        @testitem "test_b" begin
            @test 1 == 1
        end
        """)

        items = Testimonial.discover_testitems([joinpath(dir, "test")])

        # Use PartialFailRunner: test_a succeeds, test_b fails
        runner = PartialFailRunner()
        index = Testimonial.record_all(items, runner; force=true, project_dir=dir)

        @test index isa CoverageIndex
        @test index.total_discovered_items == 2
        @test index.failed_item_count == 1
        @test length(index.items) == 1  # only test_a succeeded

        # Verify persisted index also has correct metadata
        save_path = joinpath(dir, ".testimonial", "index.jls")
        Testimonial.save_index(index, save_path)
        loaded = Testimonial.load_index(save_path)
        @test loaded.total_discovered_items == 2
        @test loaded.failed_item_count == 1
    end
end