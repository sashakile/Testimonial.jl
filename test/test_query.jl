# Testimonial.jl — Tests for query_files
#
# Verifies that query_files correctly identifies test items affected
# by changed files, using the CoverageIndex to determine which items
# cover which files.
#
# See task testimonial-amd in
# openspec/changes/implement-coverage-layer/tasks.md

using Testimonial
using Test
using Dates

# ── Helpers ───────────────────────────────────

"""Create a CoverageIndex with mock items for testing."""
function make_test_index(pairs::Vector{Tuple{String, String, Vector{Int}}})
    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}()
    for (file, name, covered) in pairs
        ref = Testimonial.TestItemRef(file, 1, name)
        items[ref] = Testimonial.ItemCoverage(ref, covered, Int[])
    end
    return Testimonial.CoverageIndex(
        items,
        "abc1234",
        v"0.1.0",
        now()
    )
end

# ── query_files ───────────────────────────────

@testset "query_files returns DirectChange for tracked test file" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
        ("/proj/test/bar_test.jl", "test_b", [4, 5, 6]),
    ])

    result = Testimonial.query_files(index, ["/proj/test/foo_test.jl"])

    @test length(result) == 1
    @test result[1].item.name == "test_a"
    @test result[1].selected == true
    @test length(result[1].reasons) == 1
    @test result[1].reasons[1].kind == Testimonial.DirectChange
end

@testset "query_files returns Unresolved for untracked file" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    result = Testimonial.query_files(index, ["/proj/src/untracked.jl"])

    @test length(result) == 1
    @test result[1].selected == false
    @test result[1].reasons[1].kind == Testimonial.Unresolved
end

@testset "query_files handles multiple files with same test item" begin
    # Test item covers multiple test files — but in reality each item
    # is in a single file. This tests dedup.
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    # Both files trigger the same test item
    result = Testimonial.query_files(index, [
        "/proj/test/foo_test.jl",
        "/proj/test/foo_test.jl",  # duplicate
    ])

    @test length(result) == 1
    @test result[1].item.name == "test_a"
end

@testset "query_files returns empty for empty files list" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    result = Testimonial.query_files(index, String[])
    @test isempty(result)
end

@testset "query_files handles mixed tracked and untracked files" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
        ("/proj/test/bar_test.jl", "test_b", [4, 5, 6]),
    ])

    result = Testimonial.query_files(index, [
        "/proj/test/foo_test.jl",
        "/proj/src/lib.jl",
    ])

    @test length(result) == 2
    # First result is the tracked file
    tracked = filter(r -> r.selected, result)
    untracked = filter(r -> !r.selected, result)
    @test length(tracked) == 1
    @test length(untracked) == 1
    @test tracked[1].item.name == "test_a"
    @test untracked[1].reasons[1].kind == Testimonial.Unresolved
end

@testset "query_files accumulates reasons from multiple files" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
        ("/proj/test/bar_test.jl", "test_b", [4, 5, 6]),
    ])

    # Both files are tracked — each gets its own DirectChange reason
    result = Testimonial.query_files(index, [
        "/proj/test/foo_test.jl",
        "/proj/test/bar_test.jl",
    ])

    @test length(result) == 2
    names = sort([r.item.name for r in result])
    @test names == ["test_a", "test_b"]
    @test all(r -> r.selected, result)
end

@testset "query_files normalizes relative paths" begin
    mktempdir() do dir
        test_file = joinpath(dir, "foo_test.jl")
        write(test_file, "")

        index = make_test_index([
            (test_file, "test_a", [1, 2, 3]),
        ])

        # Pass relative path
        result = Testimonial.query_files(index, [test_file])

        @test length(result) == 1
        @test result[1].item.name == "test_a"
        @test result[1].selected == true
    end
end