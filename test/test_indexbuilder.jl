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
        ic = ItemCoverage(ref, [1, 2, 3], [4, 5])
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
            old_time = now() - Dates.Hour(12)
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(),
                "abc123",
                string(VERSION),
                v"0.1.0",
                old_time,
            )
            # 12h old, threshold 24h — not stale
            @test !is_index_stale(index; stale_threshold_hours=24)
            # 12h old, threshold 6h — stale
            @test is_index_stale(index; stale_threshold_hours=6)
        end
    end
end
# ── Schema mismatch & round-trip ──────────────

@testset "is_index_stale detects Julia version mismatch" begin
    mktempdir() do dir
        cd(dir) do
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
            ic = ItemCoverage(ref, [1, 2, 3], [4, 5])
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
