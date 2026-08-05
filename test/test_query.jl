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
        # Populate source_files so coverage_gaps can find test-file coverage
        source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
            file => (covered, Int[]),
        )
        items[ref] = Testimonial.ItemCoverage(ref, covered, Int[], source_files)
    end
    return Testimonial.CoverageIndex(
        items,
        "abc1234",
        string(VERSION),
        v"0.1.0",
        now()
    )
end

"""Create a CoverageIndex with per-item components, for scope testing."""
function make_scoped_index(pairs::Vector{Tuple{String, String, Vector{Int}, String}})
    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}()
    for (file, name, covered, component) in pairs
        ref = Testimonial.TestItemRef(file, 1, name, Symbol[], "", nothing, component)
        source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
            file => (covered, Int[]),
        )
        items[ref] = Testimonial.ItemCoverage(ref, covered, Int[], source_files)
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

@testset "coverage_gaps reports untracked source files as full gaps" begin
    index = make_test_index([
        ("/proj/test/foo_test.jl", "test_a", [1, 2, 3]),
    ])

    changed = Dict{String, Set{Int}}(
        "/proj/src/untracked.jl" => Set(1:5)
    )

    gaps = Testimonial.coverage_gaps(index, changed)

    # Untracked source file should be reported as a gap covering all changed lines
    @test length(gaps) == 1
    @test gaps[1] == Testimonial.CoverageGap("/proj/src/untracked.jl", 1, 5)
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

@testset "query_files with component scope filters results" begin
    index = make_scoped_index([
        ("/proj/pkgs/A/test/foo_test.jl", "test_a", [1, 2, 3], "PkgA"),
        ("/proj/pkgs/B/test/bar_test.jl", "test_b", [4, 5, 6], "PkgB"),
    ])

    result = Testimonial.query_files(index, ["/proj/pkgs/A/test/foo_test.jl", "/proj/pkgs/B/test/bar_test.jl"]; component="PkgA")

    @test length(result) == 1
    @test result[1].item.name == "test_a"
    @test result[1].selected == true

    # PkgB items should not appear
    @test !any(r -> r.item.name == "test_b", result)
end

@testset "direct_change_provider with component scope" begin
    index = make_scoped_index([
        ("/proj/pkgs/A/test/foo_test.jl", "test_a", [1, 2, 3], "PkgA"),
        ("/proj/pkgs/B/test/bar_test.jl", "test_b", [4, 5, 6], "PkgB"),
    ])

    result = Testimonial.direct_change_provider(index, [
        "/proj/pkgs/A/test/foo_test.jl",
        "/proj/pkgs/B/test/bar_test.jl",
    ]; component="PkgB")

    @test length(result) == 1
    @test result[1].item.name == "test_b"
end

@testset "query with component scope" begin
    # Set item components manually
    ref_a = TestItemRef("/proj/pkgs/A/test/foo_test.jl", 1, "test_a", Symbol[], "", nothing, "PkgA")
    ref_b = TestItemRef("/proj/pkgs/B/test/bar_test.jl", 1, "test_b", Symbol[], "", nothing, "PkgB")
    ic_a = ItemCoverage(ref_a, [1, 2, 3], Int[], Dict())
    ic_b = ItemCoverage(ref_b, [4, 5, 6], Int[], Dict())
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(ref_a => ic_a, ref_b => ic_b),
        "abc", string(VERSION), v"0.1.0", now()
    )

    providers = [Testimonial.direct_change_provider, Testimonial.unresolved_provider]
    changed = Dict{String, Set{Int}}(
        "/proj/pkgs/A/test/foo_test.jl" => Set([1, 2, 3]),
        "/proj/pkgs/B/test/bar_test.jl" => Set([4, 5, 6]),
    )

    results = Testimonial.query(providers, index, changed; component="PkgA")

    @test length(results) == 1
    @test results[1].item.name == "test_a"
end

@testset "runtime_edge_provider selects tests when edge file changes" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
        ("test/bar.jl", "test_bar", [4, 5, 6]),
    ])

    bar_ref = TestItemRef("test/bar.jl", 1, "test_bar")

    # Add a runtime edge: test_bar covers src/lib.jl at runtime
    index = CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        Dict{TestItemRef, Vector{Tuple{String, Int}}}(
            bar_ref => [("src/lib.jl", 42)],
        ),
    )

    # When src/lib.jl changes, test_bar should be selected
    result = Testimonial.runtime_edge_provider(index, ["src/lib.jl"])
    @test length(result) == 1
    @test result[1].item.name == "test_bar"
    @test result[1].selected == true
    @test any(r -> r.kind == AlwaysRun, result[1].reasons)
end

@testset "runtime_edge_provider returns empty when no edges match" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
    ])

    foo_ref = TestItemRef("test/foo.jl", 1, "test_foo")
    index = CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        Dict{TestItemRef, Vector{Tuple{String, Int}}}(
            foo_ref => [("src/db.jl", 10)],
        ),
    )

    # Changing a different file should not trigger
    result = Testimonial.runtime_edge_provider(index, ["src/other.jl"])
    @test isempty(result)
end

@testset "runtime_edge_provider handles empty runtime_edges" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
    ])

    # No runtime edges in index
    result = Testimonial.runtime_edge_provider(index, ["src/lib.jl"])
    @test isempty(result)
end

@testset "runtime_edge_provider integrates with query" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
        ("test/bar.jl", "test_bar", [4, 5, 6]),
    ])

    bar_ref = TestItemRef("test/bar.jl", 1, "test_bar")
    index = CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        Dict{TestItemRef, Vector{Tuple{String, Int}}}(
            bar_ref => [("src/lib.jl", 42)],
        ),
    )

    providers = [
        Testimonial.runtime_edge_provider,
    ]
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([42, 43]),
    )

    results = Testimonial.query(providers, index, changed)
    @test length(results) == 1
    @test results[1].item.name == "test_bar"
    @test results[1].selected == true
end

# ── InferenceProvider ────────────────────────

@testset "inference_provider selects tests when edge file changes" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
        ("test/bar.jl", "test_bar", [4, 5, 6]),
    ])

    bar_ref = TestItemRef("test/bar.jl", 1, "test_bar")

    # Add an inference edge: test_bar calls a method in src/lib.jl:42
    index = CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        Dict{TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(
            bar_ref => [("f", "src/lib.jl", 42, "g", "src/helper.jl", 10)],
        ),
        index.failed_item_count,
        index.total_discovered_items,
        index.available_layers,
    )

    # When src/lib.jl changes, test_bar should be selected via inference edge
    result = Testimonial.inference_provider(index, ["src/lib.jl"])
    @test length(result) == 1
    @test result[1].item.name == "test_bar"
    @test result[1].selected == true
    @test any(r -> r.kind == AlwaysRun, result[1].reasons)
end

@testset "inference_provider returns empty when no edges match" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
    ])

    foo_ref = TestItemRef("test/foo.jl", 1, "test_foo")
    index = CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        Dict{TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(
            foo_ref => [("f", "src/lib.jl", 42, "g", "src/helper.jl", 10)],
        ),
        index.failed_item_count,
        index.total_discovered_items,
        index.available_layers,
    )

    # Different file changed — no match
    result = Testimonial.inference_provider(index, ["src/other.jl"])
    @test isempty(result)
end

@testset "inference_provider handles empty inference_edges" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
    ])

    # default inference_edges is empty Dict
    result = Testimonial.inference_provider(index, ["src/lib.jl"])
    @test isempty(result)
end

@testset "inference_provider integrates with query" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
        ("test/bar.jl", "test_bar", [4, 5, 6]),
    ])

    bar_ref = TestItemRef("test/bar.jl", 1, "test_bar")
    index = CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        Dict{TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(
            bar_ref => [("f", "src/lib.jl", 42, "g", "src/helper.jl", 10)],
        ),
        index.failed_item_count,
        index.total_discovered_items,
        index.available_layers,
    )

    providers = [
        Testimonial.inference_provider,
    ]
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([42, 43]),
    )

    results = Testimonial.query(providers, index, changed)
    @test length(results) == 1
    @test results[1].item.name == "test_bar"
    @test results[1].selected == true
end

@testset "inference_provider creates provenance link with INFERRED LayerKind" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
    ])

    fref = TestItemRef("test/foo.jl", 1, "test_foo")
    index = CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        Dict{TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(
            fref => [("f", "src/lib.jl", 42, "g", "src/helper.jl", 10)],
        ),
        index.failed_item_count,
        index.total_discovered_items,
        index.available_layers,
    )

    results = Testimonial.inference_provider(index, ["src/lib.jl"])
    @test length(results) == 1
    r = results[1]
    @test length(r.reasons) == 1
    reason = r.reasons[1]
    @test !isempty(reason.chain)
    link = reason.chain[1]
    @test link.layer == Testimonial.INFERRED
    @test link.content_unit == "src/lib.jl"
end

# ── StaticProvider ────────────────────────

@testset "static_provider selects tests when source file has static edges" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
        ("test/bar.jl", "test_bar", [4, 5, 6]),
    ])

    foo_ref = Testimonial.TestItemRef("test/foo.jl", 1, "test_foo")
    bar_ref = Testimonial.TestItemRef("test/bar.jl", 1, "test_bar")

    # Add static edges: src/lib.jl -> {test_foo, test_bar}
    index = Testimonial.CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        index.inference_edges,
        Dict{String, Set{Testimonial.TestItemRef}}(
            "src/lib.jl" => Set([foo_ref, bar_ref]),
        ),
        index.layer_data,
        index.failed_item_count,
        index.total_discovered_items,
        index.available_layers,
    )

    # When src/lib.jl changes, both test_foo and test_bar should be selected
    result = Testimonial.static_provider(index, ["src/lib.jl"])
    @test length(result) == 2
    names = sort([r.item.name for r in result])
    @test names == ["test_bar", "test_foo"]
    @test all(r -> r.selected == true, result)
    @test all(r -> any(re -> re.kind == Testimonial.AlwaysRun, r.reasons), result)
end

@testset "static_provider returns empty when no static edges match" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
    ])

    foo_ref = Testimonial.TestItemRef("test/foo.jl", 1, "test_foo")
    index = Testimonial.CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        index.inference_edges,
        Dict{String, Set{Testimonial.TestItemRef}}(
            "src/lib.jl" => Set([foo_ref]),
        ),
        index.layer_data,
        index.failed_item_count,
        index.total_discovered_items,
        index.available_layers,
    )

    # Different file changed — no match
    result = Testimonial.static_provider(index, ["src/other.jl"])
    @test isempty(result)
end

@testset "static_provider handles empty static_edges" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
    ])

    # default static_edges is empty Dict
    result = Testimonial.static_provider(index, ["src/lib.jl"])
    @test isempty(result)
end

@testset "static_provider integrates with query" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
        ("test/bar.jl", "test_bar", [4, 5, 6]),
    ])

    foo_ref = Testimonial.TestItemRef("test/foo.jl", 1, "test_foo")
    index = Testimonial.CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        index.inference_edges,
        Dict{String, Set{Testimonial.TestItemRef}}(
            "src/lib.jl" => Set([foo_ref]),
        ),
        index.layer_data,
        index.failed_item_count,
        index.total_discovered_items,
        index.available_layers,
    )

    providers = [
        Testimonial.static_provider,
    ]
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([42, 43]),
    )

    results = Testimonial.query(providers, index, changed)
    @test length(results) == 1
    @test results[1].item.name == "test_foo"
    @test results[1].selected == true
end

@testset "static_provider creates provenance link with STATIC LayerKind" begin
    index = make_test_index([
        ("test/foo.jl", "test_foo", [1, 2, 3]),
    ])

    fref = Testimonial.TestItemRef("test/foo.jl", 1, "test_foo")
    index = Testimonial.CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        index.inference_edges,
        Dict{String, Set{Testimonial.TestItemRef}}(
            "src/lib.jl" => Set([fref]),
        ),
        index.layer_data,
        index.failed_item_count,
        index.total_discovered_items,
        index.available_layers,
    )

    results = Testimonial.static_provider(index, ["src/lib.jl"])
    @test length(results) == 1
    r = results[1]
    @test length(r.reasons) == 1
    reason = r.reasons[1]
    @test !isempty(reason.chain)
    link = reason.chain[1]
    @test link.layer == Testimonial.STATIC
    @test link.content_unit == "src/lib.jl"
end

# ── coverage_provider (source-file attribution) ───

"""Create a CoverageIndex with source_files coverage for testing."""
function make_index_with_source_files(
    test_file::String,
    item_name::String,
    covered_lines::Vector{Int},
    source_files::Dict{String, Tuple{Vector{Int}, Vector{Int}}},
)
    ref = Testimonial.TestItemRef(test_file, 1, item_name)
    ic = Testimonial.ItemCoverage(ref, covered_lines, Int[], source_files)
    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(ref => ic)
    return Testimonial.CoverageIndex(
        items, "abc1234", string(VERSION), v"0.1.0", now()
    )
end

@testset "query_files returns Unresolved for source-file change (test-file-only lookup)" begin
    # A test item covers a source file via source_files, but query_files
    # only looks at test-file paths — so it returns Unresolved.
    source_files = Dict(
        "src/lib.jl" => ([10, 20, 30], [15, 25]),
    )
    index = make_index_with_source_files(
        "/proj/test/foo_test.jl", "test_a", [1, 2, 3], source_files,
    )

    # query_files only checks if the changed file IS a test file
    result = Testimonial.query_files(index, ["src/lib.jl"])

    # Returns Unresolved — source file not in test-file index
    @test length(result) == 1
    @test result[1].selected == false
    @test result[1].reasons[1].kind == Testimonial.Unresolved
end

@testset "coverage_provider selects test when source file changed" begin
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([20]),  # line 20 changed, which is covered
    )
    source_files = Dict(
        "src/lib.jl" => ([10, 20, 30], [15, 25]),
    )
    index = make_index_with_source_files(
        "/proj/test/foo_test.jl", "test_a", [1, 2, 3], source_files,
    )

    provider = Testimonial.coverage_provider(changed)
    results = provider(index, ["src/lib.jl"])

    @test length(results) == 1
    @test results[1].selected == true
    @test results[1].item.name == "test_a"
    @test length(results[1].reasons) == 1
    @test results[1].reasons[1].kind == Testimonial.DirectChange
    # Should have a provenance chain with COVERAGE layer
    @test !isempty(results[1].reasons[1].chain)
    @test results[1].reasons[1].chain[1].layer == Testimonial.COVERAGE
end

@testset "query with coverage_provider selects test for covered source change" begin
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([20]),  # line 20 changed, covered
    )
    source_files = Dict(
        "src/lib.jl" => ([10, 20, 30], [15, 25]),
    )
    index = make_index_with_source_files(
        "/proj/test/foo_test.jl", "test_a", [1, 2, 3], source_files,
    )

    providers = [
        Testimonial.direct_change_provider,
        Testimonial.coverage_provider(changed),
        Testimonial.unresolved_provider,
    ]
    results = Testimonial.query(providers, index, changed)

    # Two results: one for the covered test (selected), one for the
    # source file (unresolved — not a test file, but covered by the test)
    selected_results = [r for r in results if r.selected]
    @test length(selected_results) == 1
    @test selected_results[1].item.name == "test_a"
end

@testset "coverage_provider unchanged source line does not select test" begin
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([15]),  # line 15 changed, NOT covered (in uncovered)
    )
    source_files = Dict(
        "src/lib.jl" => ([10, 20, 30], [15, 25]),
    )
    index = make_index_with_source_files(
        "/proj/test/foo_test.jl", "test_a", [1, 2, 3], source_files,
    )

    provider = Testimonial.coverage_provider(changed)
    results = provider(index, ["src/lib.jl"])

    @test isempty(results)
end

@testset "coverage_provider with multiple source files" begin
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([20]),
        "src/utils.jl" => Set([50]),
    )
    source_files = Dict(
        "src/lib.jl" => ([10, 20, 30], Int[]),
        "src/utils.jl" => ([40, 50, 60], Int[]),
    )
    index = make_index_with_source_files(
        "/proj/test/foo_test.jl", "test_a", [1, 2, 3], source_files,
    )

    provider = Testimonial.coverage_provider(changed)
    results = provider(index, ["src/lib.jl", "src/utils.jl"])

    @test length(results) == 1
    @test results[1].selected == true
    @test length(results[1].reasons[1].chain) == 2  # two changed lines covered
end

# ── File-level query support (line==0 items) ───

@testset "coverage_provider selects file-level test when source file changed" begin
    # File-level test item (line=0) with source_files coverage
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([20]),
    )
    source_files = Dict(
        "src/lib.jl" => ([10, 20, 30], [15, 25]),
    )
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 0, "foo_test.jl")
    ic = Testimonial.ItemCoverage(ref, Int[], Int[], source_files)
    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(ref => ic)
    index = Testimonial.CoverageIndex(
        items, "abc1234", string(VERSION), v"0.1.0", now()
    )

    provider = Testimonial.coverage_provider(changed)
    results = provider(index, ["src/lib.jl"])

    @test length(results) == 1
    @test results[1].selected == true
    @test results[1].item.name == "foo_test.jl"
    @test results[1].item.line == 0
end

@testset "mixed query selects both file-level and per-item tests" begin
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([20]),
    )

    # File-level test covering src/lib.jl
    file_ref = Testimonial.TestItemRef("/proj/test/set_test.jl", 0, "set_test.jl")
    file_ic = Testimonial.ItemCoverage(file_ref, Int[], Int[], Dict(
        "src/lib.jl" => ([10, 20, 30], [15, 25]),
    ))

    # Per-item @testitem covering src/lib.jl
    item_ref = Testimonial.TestItemRef("/proj/test/item_test.jl", 10, "test_a")
    item_ic = Testimonial.ItemCoverage(item_ref, [1, 2, 3], Int[], Dict(
        "src/lib.jl" => ([10, 20, 30], [15, 25]),
    ))

    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(
        file_ref => file_ic,
        item_ref => item_ic,
    )
    index = Testimonial.CoverageIndex(
        items, "abc1234", string(VERSION), v"0.1.0", now()
    )

    providers = [
        Testimonial.direct_change_provider,
        Testimonial.coverage_provider(changed),
        Testimonial.unresolved_provider,
    ]
    results = Testimonial.query(providers, index, changed)

    # Should have selected both file-level and per-item tests
    selected = [r for r in results if r.selected]
    @test length(selected) == 2

    names = sort([r.item.name for r in selected])
    @test names == ["set_test.jl", "test_a"]

    # The file-level test should have line==0
    file_result = filter(r -> r.item.line == 0, selected)
    @test length(file_result) == 1
    @test file_result[1].item.name == "set_test.jl"
end

@testset "no duplicate selections for file-level and per-item covering same source" begin
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([20]),
    )

    source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
        "src/lib.jl" => ([10, 20, 30], [15, 25]),
    )

    # Same file, different names — both cover src/lib.jl
    ref1 = Testimonial.TestItemRef("/proj/test/foo_test.jl", 0, "foo_test.jl")
    ic1 = Testimonial.ItemCoverage(ref1, Int[], Int[], source_files)

    ref2 = Testimonial.TestItemRef("/proj/test/foo_test.jl", 10, "test_a")
    ic2 = Testimonial.ItemCoverage(ref2, [1, 2, 3], Int[], source_files)

    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(ref1 => ic1, ref2 => ic2)
    index = Testimonial.CoverageIndex(
        items, "abc1234", string(VERSION), v"0.1.0", now()
    )

    provider = Testimonial.coverage_provider(changed)
    results = provider(index, ["src/lib.jl"])

    # Each item should appear exactly once
    @test length(results) == 2
    @test all(r.selected for r in results)
    # Different names — no duplicates
    @test sort([r.item.name for r in results]) == ["foo_test.jl", "test_a"]
end

@testset "file-level test with no coverage data returns empty" begin
    changed = Dict{String, Set{Int}}(
        "src/lib.jl" => Set([20]),
    )

    # File-level test with EMPTY source_files
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 0, "foo_test.jl")
    ic = Testimonial.ItemCoverage(ref, Int[], Int[], Dict())
    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(ref => ic)
    index = Testimonial.CoverageIndex(
        items, "abc1234", string(VERSION), v"0.1.0", now()
    )

    provider = Testimonial.coverage_provider(changed)
    results = provider(index, ["src/lib.jl"])

    @test isempty(results)
end
