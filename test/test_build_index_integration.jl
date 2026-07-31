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

# ── Mixed-mode integration ─────────────────────

"""Create a scratch repo with both @testitem and @testset blocks."""
function create_mixed_scratch_repo(dir::String)
    test_dir = joinpath(dir, "test")
    src_dir = joinpath(dir, "src")
    mkpath(test_dir)
    mkpath(src_dir)

    # File with @testitems (per-item recording)
    write(joinpath(test_dir, "item_test.jl"), """
    @testitem "test_x" begin
        @test 1 == 1
    end

    @testitem "test_y" begin
        @test 2 == 2
    end
    """)

    # File with @testset blocks (file-level recording)
    write(joinpath(test_dir, "set_test.jl"), """
    @testset "outer" begin
        @test 3 == 3
    end

    @testset "inner" begin
        @test 4 == 4
    end
    """)

    # File with no test blocks (triggers file-level fallback, line=0)
    write(joinpath(test_dir, "plain_test.jl"), """
    @test 5 == 5
    @test 6 == 6
    """)

    # Source file
    write(joinpath(src_dir, "Lib.jl"), """
    module Lib
        foo() = 42
    end
    """)

    return test_dir
end

@testset "record_all with mixed-mode scratch repo produces both item types" begin
    mktempdir() do dir
        cd(dir) do
            test_dir = create_mixed_scratch_repo(dir)
            runner = MockRunner()

            # Discover ALL test blocks
            items = Testimonial.discover_all_test_blocks([test_dir])
            @test length(items) > 0

            # Record all items
            index = record_all(items, runner; force=true)

            # Should have items of both types
            item_items = [ic for (ref, ic) in index.items if ref.line > 0]
            file_items = [ic for (ref, ic) in index.items if ref.line == 0]

            @test !isempty(item_items)
            @test !isempty(file_items)

            # @testset items in the same file collapse to a single file-level
            # entry (since all are recorded via record_file for the same file).
            # So total items is less than raw discovery count.
            @test length(index.items) == 4  # 2 @testitem + 1 file-level (set_test) + 1 file-level (plain_test)

            # File-level items should have basename as name
            for (ref, ic) in index.items
                if ref.line == 0
                    @test ref.name == basename(ref.file)
                end
            end
        end
    end
end

@testset "Mixed-mode index round-trips through cache files" begin
    mktempdir() do dir
        cd(dir) do
            test_dir = create_mixed_scratch_repo(dir)
            runner = MockRunner()

            items = Testimonial.discover_all_test_blocks([test_dir])
            original = record_all(items, runner; force=true)

            # Reconstruct index from cache files
            reconstructed = build_index(".testimonial/items")

            @test length(reconstructed.items) == length(original.items)

            # Verify file-level items are preserved
            orig_file_items = [ic for (ref, ic) in original.items if ref.line == 0]
            recon_file_items = [ic for (ref, ic) in reconstructed.items if ref.line == 0]
            @test length(recon_file_items) == length(orig_file_items)

            # Verify @testitem items are preserved
            orig_item_items = [ic for (ref, ic) in original.items if ref.line > 0]
            recon_item_items = [ic for (ref, ic) in reconstructed.items if ref.line > 0]
            @test length(recon_item_items) == length(orig_item_items)
        end
    end
end

@testset "Mixed-mode query selects both @testitem and file-level tests" begin
    mktempdir() do dir
        cd(dir) do
            test_dir = create_mixed_scratch_repo(dir)
            runner = MockRunner()

            items = Testimonial.discover_all_test_blocks([test_dir])
            index = record_all(items, runner; force=true)

            # Simulate a change to a test file — both @testitem and file-level
            # tests should be selected by direct_change_provider.
            # Note: MockRunner record_file returns empty source_files, so
            # coverage_provider would not find source-file coverage. We test
            # the direct_change_provider path instead (test-file change).
            changed = Dict{String, Set{Int}}(
                "test/item_test.jl" => Set([1, 2, 3]),
                "test/set_test.jl" => Set([1, 2, 3]),
            )

            # Use the provider pipeline (same as CLI)
            providers = [
                Testimonial.direct_change_provider,
                Testimonial.coverage_provider(changed),
                Testimonial.unresolved_provider,
            ]
            results = Testimonial.query(providers, index, changed)

            selected = [r for r in results if r.selected]
            @test !isempty(selected)

            # Should have at least one file-level item selected
            file_selected = [r for r in selected if r.item.line == 0]
            @test !isempty(file_selected)
        end
    end
end