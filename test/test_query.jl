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
        items[ref] = Testimonial.ItemCoverage(ref, covered, Int[], Dict())
    end
    return Testimonial.CoverageIndex(
        items,
        "abc1234",
        string(VERSION),
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

# ── coverage_gaps ────────────────────────────

@testset "coverage_gaps finds gaps in changed file" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [2, 4, 6]),
    ])

    changed = Dict{String, Set{Int}}(
        "/proj/test/foo_test.jl" => Set([1, 2, 3, 4, 5, 6])
    )

    gaps = Testimonial.coverage_gaps(index, changed)

    @test length(gaps) == 3
    @test gaps[1] == Testimonial.CoverageGap("/proj/test/foo_test.jl", 1, 1)
    @test gaps[2] == Testimonial.CoverageGap("/proj/test/foo_test.jl", 3, 3)
    @test gaps[3] == Testimonial.CoverageGap("/proj/test/foo_test.jl", 5, 5)
end

@testset "coverage_gaps merges consecutive uncovered lines" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 10]),
    ])

    changed = Dict{String, Set{Int}}(
        "/proj/test/foo_test.jl" => Set(2:9)
    )

    gaps = Testimonial.coverage_gaps(index, changed)

    @test length(gaps) == 1
    @test gaps[1] == Testimonial.CoverageGap("/proj/test/foo_test.jl", 2, 9)
end

@testset "coverage_gaps ignores covered lines" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", collect(1:10)),
    ])

    changed = Dict{String, Set{Int}}(
        "/proj/test/foo_test.jl" => Set(1:10)
    )

    gaps = Testimonial.coverage_gaps(index, changed)
    @test isempty(gaps)
end

@testset "coverage_gaps ignores untracked files" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    changed = Dict{String, Set{Int}}(
        "/proj/src/untracked.jl" => Set(1:5)
    )

    gaps = Testimonial.coverage_gaps(index, changed)
    @test isempty(gaps)
end

@testset "coverage_gaps returns empty for empty changed map" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    gaps = Testimonial.coverage_gaps(index, Dict{String, Set{Int}}())
    @test isempty(gaps)
end

@testset "coverage_gaps aggregates across multiple items" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
        ("/proj/test/foo_test.jl", "test_b", [4, 5, 6]),
    ])

    changed = Dict{String, Set{Int}}(
        "/proj/test/foo_test.jl" => Set(1:10)
    )

    gaps = Testimonial.coverage_gaps(index, changed)

    # Lines 1-6 are covered (by test_a + test_b), lines 7-10 are not
    @test length(gaps) == 1
    @test gaps[1] == Testimonial.CoverageGap("/proj/test/foo_test.jl", 7, 10)
end

# ── nearest_covered_lines ─────────────────────

@testset "nearest_covered_lines finds nearest covered before and after" begin
    mktempdir() do dir
        test_file = joinpath(dir, "nearest_test.jl")
        write(test_file, """
line 1
line 2
line 3
line 4
line 5
""")

        index = make_test_index([
            (test_file, "test_a", [2, 4]),
        ])

        before, after = Testimonial.nearest_covered_lines(index, test_file, 3)

        @test before == 2
        @test after == 4
    end
end

@testset "nearest_covered_lines returns nothing when no covered lines" begin
    mktempdir() do dir
        test_file = joinpath(dir, "none_test.jl")
        write(test_file, "line 1\n")

        index = make_test_index([
            (test_file, "test_a", Int[]),
        ])

        before, after = Testimonial.nearest_covered_lines(index, test_file, 1)

        @test before === nothing
        @test after === nothing
    end
end

@testset "nearest_covered_lines at exact covered line" begin
    mktempdir() do dir
        test_file = joinpath(dir, "exact_test.jl")
        write(test_file, """
line 1
line 2
""")

        index = make_test_index([
            (test_file, "test_a", [1, 2]),
        ])

        before, after = Testimonial.nearest_covered_lines(index, test_file, 1)

        @test before == 1
        @test after == 1
    end
end

@testset "nearest_covered_lines beyond last line" begin
    mktempdir() do dir
        test_file = joinpath(dir, "beyond_test.jl")
        write(test_file, """
line 1
line 2
line 3
""")

        index = make_test_index([
            (test_file, "test_a", [2]),
        ])

        before, after = Testimonial.nearest_covered_lines(index, test_file, 5)

        @test before == 2
        @test after === nothing
    end
end

# ── Provider-based query ─────────────────────

@testset "direct_change_provider returns DirectChange for tracked files" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    result = Testimonial.direct_change_provider(index, ["/proj/test/foo_test.jl"])

    @test length(result) == 1
    @test result[1].item.name == "test_a"
    @test result[1].selected == true
    @test result[1].reasons[1].kind == Testimonial.DirectChange
end

@testset "unresolved_provider returns Unresolved for untracked files" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    result = Testimonial.unresolved_provider(index, ["/proj/src/untracked.jl"])

    @test length(result) == 1
    @test result[1].selected == false
    @test result[1].reasons[1].kind == Testimonial.Unresolved
    @test result[1].fallback_reason !== nothing
    @test occursin("unresolved file", result[1].fallback_reason)
end

@testset "unresolved_provider skips files tracked in index" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    result = Testimonial.unresolved_provider(index, ["/proj/test/foo_test.jl"])
    @test isempty(result)
end

@testset "query accumulates reasons across providers" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    providers = [Testimonial.direct_change_provider, Testimonial.unresolved_provider]
    changed = Dict{String, Set{Int}}(
        "/proj/test/foo_test.jl" => Set([1, 2, 3]),
        "/proj/src/lib.jl" => Set([10, 11, 12]),
    )

    results = Testimonial.query(providers, index, changed)

    @test length(results) >= 1
    tracked = filter(r -> r.selected, results)
    untracked = filter(r -> !r.selected, results)
    @test length(tracked) == 1
    @test length(untracked) == 1
    @test tracked[1].item.name == "test_a"
    @test untracked[1].reasons[1].kind == Testimonial.Unresolved
end

@testset "query deduplicates items from same provider" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    providers = [Testimonial.direct_change_provider, Testimonial.direct_change_provider]
    changed = Dict{String, Set{Int}}(
        "/proj/test/foo_test.jl" => Set([1, 2, 3]),
    )

    results = Testimonial.query(providers, index, changed)

    # Should be deduplicated to one result with two reasons
    @test length(results) == 1
    @test length(results[1].reasons) == 2
    @test results[1].selected == true
end

@testset "query returns empty for empty changed" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    providers = [Testimonial.direct_change_provider]
    results = Testimonial.query(providers, index, Dict{String, Set{Int}}())
    @test isempty(results)
end

@testset "query returns empty when no providers match" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    # Empty provider list
    empty_providers = Function[]
    changed = Dict{String, Set{Int}}(
        "/proj/test/foo_test.jl" => Set([1, 2, 3]),
    )

    results = Testimonial.query(empty_providers, index, changed)
    @test isempty(results)
end