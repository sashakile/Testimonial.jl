# Testimonial.jl — Tests for IndexBuilder record_item
#
# Verifies the single-item recording API works end-to-end.
# Integration tests for actual subprocess spawning are in test_wah.jl.
#
# See REC-007 and task 6.3 in
# openspec/changes/implement-coverage-layer/tasks.md

using Testimonial
using Test
using Serialization
using Dates

@testset "record_item returns ItemCoverage" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_foo.jl")
        write(test_file, """
        @testitem "my_test" begin
            @test 1 == 1
        end
        """)

        result = Testimonial.record_item(test_file, "my_test")
        @test result isa Testimonial.ItemCoverage
        @test result.item.name == "my_test"
    end
end

@testset "record_item returns nothing for unknown item" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_bar.jl")
        write(test_file, """
        @testitem "known" begin
            @test 1 == 1
        end
        """)

        result = Testimonial.record_item(test_file, "unknown")
        @test result === nothing
    end
end

@testset "record_item fails for nonexistent file" begin
    @test_throws Exception Testimonial.record_item("/nonexistent/path.jl", "foo")
end

# ── save_index / load_index ────────────────────

@testset "save_index persists CoverageIndex" begin
    mktempdir() do dir
        path = joinpath(dir, "index.jls")
        ref = TestItemRef("test/foo.jl", 10, "test_a", Symbol[], "abc123")
        ic = ItemCoverage(ref, [1, 2, 3], [4, 5], Dict())
        index = CoverageIndex(
            Dict{TestItemRef, ItemCoverage}(ref => ic),
            "abc123",
            string(VERSION),
            v"0.1.0",
            now(),
        )

        save_index(index, path)
        @test isfile(path)

        loaded = load_index(path)
        @test loaded isa CoverageIndex
        @test length(loaded.items) == 1
        @test loaded.git_hash == "abc123"
        @test loaded.julia_version == string(VERSION)
        @test loaded.schema_version == v"0.1.0"
    end
end

@testset "load_index returns nothing for missing file" begin
    result = load_index("/nonexistent/path.jls")
    @test result === nothing
end

@testset "load_index returns nothing for corrupted file" begin
    mktempdir() do dir
        path = joinpath(dir, "bad.jls")
        write(path, "not valid serialized data")
        result = load_index(path)
        @test result === nothing
    end
end

@testset "save_index creates parent directories" begin
    mktempdir() do dir
        path = joinpath(dir, "a", "b", "index.jls")
        index = CoverageIndex(
            Dict{TestItemRef, ItemCoverage}(),
            "",
            string(VERSION),
            v"0.1.0",
            now(),
        )
        save_index(index, path)
        @test isfile(path)
    end
end

# ── is_index_stale ─────────────────────────────

@testset "is_index_stale returns false for fresh index" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)
            run(`git commit --allow-empty -m init`)
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            @test !is_index_stale(index)
        end
    end
end

@testset "is_index_stale returns true for old index" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)
            run(`git commit --allow-empty -m init`)
            old_time = now() - Dates.Day(2)
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(),
                "abc123",
                string(VERSION),
                v"0.1.0",
                old_time,
            )
            @test is_index_stale(index; stale_threshold_hours=24)
        end
    end
end

@testset "is_index_stale respects custom threshold" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)
            run(`git commit --allow-empty -m init`)
            old_time = now() - Dates.Hour(12)
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(),
                "abc123",
                string(VERSION),
                v"0.1.0",
                old_time,
            )
            @test !is_index_stale(index; stale_threshold_hours=24)
            @test is_index_stale(index; stale_threshold_hours=6)
        end
    end
end

@testset "is_index_stale detects Julia version mismatch" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)
            run(`git commit --allow-empty -m init`)
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(),
                "abc123",
                "1.0.0",
                v"0.1.0",
                now(),
            )
            @test is_index_stale(index)
        end
    end
end

@testset "is_index_stale treats unknown git state as stale (testimonial-3yem.7)" begin
    mktempdir() do dir
        cd(dir) do
            # No git repo — _is_dirty() will fail, treated as stale
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            @test is_index_stale(index)
        end
    end
end

@testset "load_index rejects non-CoverageIndex data" begin
    mktempdir() do dir
        cd(dir) do
            path = joinpath(dir, "index.jls")
            open(path, "w") do io
                serialize(io, "not_a_coverage_index")
            end
            result = load_index(path)
            @test result === nothing
        end
    end
end

@testset "load_index round-trip preserves all fields" begin
    mktempdir() do dir
        cd(dir) do
            ref = TestItemRef("test/foo.jl", 10, "test_a", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1, 2, 3], [4, 5], Dict())
            original = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            path = joinpath(dir, "index.jls")
            save_index(original, path)
            loaded = load_index(path)

            @test loaded isa CoverageIndex
            @test loaded.git_hash == original.git_hash
            @test loaded.julia_version == original.julia_version
            @test loaded.schema_version == original.schema_version
            @test length(loaded.items) == length(original.items)

            for (ref, ic) in original.items
                @test haskey(loaded.items, ref)
                @test loaded.items[ref].covered_lines == ic.covered_lines
                @test loaded.items[ref].uncovered_lines == ic.uncovered_lines
            end
        end
    end
end

# ── clean_cache ───────────────────────────────

@testset "clean_cache removes orphaned records" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial/items")
            mkpath("test")

            # Create a current test file
            write("test/current_test.jl", """@testitem "current_item" begin @test 1==1 end""")

            # Discover to get the real file_hash
            items = discover_testitems(["test/"])
            @test length(items) == 1
            ref = items[1]

            # Create a valid current record using the real hash
            ic = ItemCoverage(ref, [1], Int[], Dict())
            key = "$(ref.file_hash)-$(ref.name)"
            open(".testimonial/items/$(key).jls", "w") do io
                serialize(io, ic)
            end

            # Create an orphaned record (no matching @testitem)
            orphan_ref = TestItemRef("/gone/test.jl", 1, "orphaned", Symbol[], "deadbeef")
            orphan_ic = ItemCoverage(orphan_ref, [1], Int[], Dict())
            open(".testimonial/items/deadbeef-orphaned.jls", "w") do io
                serialize(io, orphan_ic)
            end

            # Create a corrupted file
            write(".testimonial/items/corrupted.jls", "not valid")

            @test length(readdir(".testimonial/items")) == 3

            n_removed = clean_cache()
            @test n_removed == 2  # orphan + corrupted

            remaining = readdir(".testimonial/items")
            @test length(remaining) == 1
            @test startswith(remaining[1], "$(ref.file_hash)-current_item")
        end
    end
end

@testset "clean_cache keeps valid records" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial/items")
            mkpath("test")

            write("test/foo_test.jl", """@testitem "test_a" begin @test 1==1 end""")
            write("test/bar_test.jl", """@testitem "test_b" begin @test 2==2 end""")

            items = discover_testitems(["test/"])
            @test length(items) == 2

            # Create cache records that match current items
            for ref in items
                ic = ItemCoverage(ref, [1], Int[], Dict())
                open(".testimonial/items/$(ref.file_hash)-$(ref.name).jls", "w") do io
                    serialize(io, ic)
                end
            end

            n_removed = clean_cache()
            @test n_removed == 0  # nothing to remove
            @test length(readdir(".testimonial/items")) == 2
        end
    end
end

@testset "clean_cache handles empty items directory" begin
    mktempdir() do dir
        cd(dir) do
            n_removed = clean_cache()
            @test n_removed == 0
        end
    end
end
