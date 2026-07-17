# Testimonial.jl — Tests for CLI entry points
#
# Tests index_info, save_index, load_index, and other CLI functions.
#
# See SEL-007 in
# openspec/changes/implement-coverage-layer/specs/smart-selection/spec.md

using Testimonial
using Test

@testset "index_info returns metadata for existing index" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            # Create a simple CoverageIndex and persist it
            ref = TestItemRef("test/foo.jl", 10, "test_a", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1, 2, 3], [4, 5])
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            info = index_info()
            @test info isa NamedTuple
            @test info.index_present == true
            @test info.git_sha == "abc123"
            @test info.julia_version == string(VERSION)
            @test info.schema_version == 1
            @test info.item_count == 1
            @test info.file_count == 1
            @test info.age_hours isa Float64
        end
    end
end

@testset "index_info returns empty metadata when no index exists" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            info = index_info()
            @test info isa NamedTuple
            @test info.index_present == false
            @test info.item_count == 0
            @test info.git_sha == ""
            @test info.file_count == 0
        end
    end
end

@testset "index_info computes file_count correctly" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            # Items from two files
            ref1 = TestItemRef("test/a_test.jl", 10, "test_a", Symbol[], "abc123")
            ref2 = TestItemRef("test/b_test.jl", 5, "test_b", Symbol[], "def456")
            ic1 = ItemCoverage(ref1, [1], Int[])
            ic2 = ItemCoverage(ref2, [10], Int[])
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref1 => ic1, ref2 => ic2),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            info = index_info()
            @test info.item_count == 2
            @test info.file_count == 2
        end
    end
end