# Testimonial.jl — Integration test for build_index
#
# Verifies the full round-trip: record_all → cache files → build_index.
# Uses MockRunner to avoid subprocess overhead while testing the real
# cache serialization and index reconstruction pipelines.
#
# See REC-008 and task testimonial-99u in
# openspec/changes/implement-coverage-layer/tasks.md

using Testimonial
using Test
using Serialization

# ── Helpers ───────────────────────────────────

"""Create a scratch monorepo with @testitem files for integration testing."""
function create_scratch_monorepo(dir::String)
    test_dir = joinpath(dir, "test")
    src_dir = joinpath(dir, "src")
    mkpath(test_dir)
    mkpath(src_dir)

    # File with two @testitems
    write(joinpath(test_dir, "widget_test.jl"), """
    @testitem "test_widget_a" begin
        @test 1 == 1
    end

    @testitem "test_widget_b" begin
        @test 2 == 2
    end
    """)

    # File with one @testitem
    write(joinpath(test_dir, "gadget_test.jl"), """
    @testitem "test_gadget" begin
        @test 3 == 3
    end
    """)

    # Source file (no @testitems, but present for realism)
    write(joinpath(src_dir, "Widget.jl"), """
    module Widget
        greet() = "hello"
    end
    """)

    return test_dir
end

# ── Integration tests ─────────────────────────

@testset "build_index round-trip from scratch monorepo" begin
    mktempdir() do dir
        cd(dir) do
            test_dir = create_scratch_monorepo(dir)

            # Discover @testitems
            items = Testimonial.discover_testitems([test_dir])
            @test length(items) == 3

            # Record all items with MockRunner (force=true, no cache)
            runner = MockRunner()
            index = record_all(items, runner; force=true)

            @test length(index.items) == 3

            # Reconstruct index from cache files written by record_all
            reconstructed = build_index(".testimonial/items")

            @test reconstructed isa CoverageIndex
            @test length(reconstructed.items) == 3

            # Verify reconstructed items match original names
            original_names = sort([ic.item.name for (_, ic) in index.items])
            reconstructed_names = sort([ic.item.name for (_, ic) in reconstructed.items])
            @test reconstructed_names == original_names
            @test reconstructed_names == ["test_gadget", "test_widget_a", "test_widget_b"]
        end
    end
end

@testset "build_index preserves coverage data through round-trip" begin
    mktempdir() do dir
        cd(dir) do
            test_dir = create_scratch_monorepo(dir)
            items = Testimonial.discover_testitems([test_dir])
            runner = MockRunner()

            # Record all items
            original = record_all(items, runner; force=true)

            # Reconstruct from cache
            reconstructed = build_index(".testimonial/items")

            # Verify each item's coverage data is preserved
            for (ref, ic) in original.items
                @test haskey(reconstructed.items, ref)
                ric = reconstructed.items[ref]
                @test ric.covered_lines == ic.covered_lines
                @test ric.uncovered_lines == ic.uncovered_lines
                @test ric.item.file_hash == ref.file_hash
                @test ric.item.name == ref.name
                @test ric.item.line == ref.line
                @test ric.item.tags == ref.tags
            end
        end
    end
end

@testset "build_index after incremental record" begin
    mktempdir() do dir
        cd(dir) do
            test_dir = create_scratch_monorepo(dir)
            items = Testimonial.discover_testitems([test_dir])

            # First pass: force=true records everything
            runner1 = MockRunner()
            index1 = record_all(items, runner1; force=true)

            # Second pass: incremental=true, should use cached records
            runner2 = MockRunner()
            index2 = record_all(items, runner2; incremental=true)

            # build_index should reconstruct 3 items from cache
            reconstructed = build_index(".testimonial/items")

            @test length(reconstructed.items) == 3
            @test length(index2.items) == 3

            # Both the full record and the incremental build should produce
            # the same index (same items, same coverage data)
            names1 = sort([ic.item.name for (_, ic) in index1.items])
            names2 = sort([ic.item.name for (_, ic) in reconstructed.items])
            @test names1 == names2
        end
    end
end

@testset "build_index from nonexistent directory returns empty index" begin
    mktempdir() do dir
        cd(dir) do
            index = build_index("/nonexistent/items")
            @test index isa CoverageIndex
            @test isempty(index.items)
        end
    end
end

@testset "build_index recovers from corrupted cache files" begin
    mktempdir() do dir
        cd(dir) do
            test_dir = create_scratch_monorepo(dir)
            items = Testimonial.discover_testitems([test_dir])
            runner = MockRunner()

            # Record items
            record_all(items, runner; force=true)

            # Corrupt one cache file
            items_dir = ".testimonial/items"
            jls_files = filter(f -> endswith(f, ".jls"), readdir(items_dir))
            @test length(jls_files) == 3

            # Overwrite the first file with garbage
            write(joinpath(items_dir, jls_files[1]), "not valid serialized data")

            # build_index should gracefully skip the corrupted file
            reconstructed = build_index(items_dir)
            @test length(reconstructed.items) == 2

            # The remaining items should still be valid
            for (_, ic) in reconstructed.items
                @test ic isa ItemCoverage
            end
        end
    end
end

@testset "build_index handles single item correctly" begin
    mktempdir() do dir
        cd(dir) do
            # Single file with one @testitem
            test_dir = joinpath(dir, "test")
            mkpath(test_dir)
            write(joinpath(test_dir, "single_test.jl"), """
            @testitem "only_test" begin
                @test 42 == 42
            end
            """)

            items = Testimonial.discover_testitems([test_dir])
            @test length(items) == 1

            runner = MockRunner()
            index = record_all(items, runner; force=true)
            @test length(index.items) == 1

            reconstructed = build_index(".testimonial/items")
            @test length(reconstructed.items) == 1

            ric = first(values(reconstructed.items))
            @test ric.item.name == "only_test"
        end
    end
end