# Testimonial.jl — Integration tests for inference layer end-to-end
#
# Exercises the full query pipeline with multiple providers (runtime edges +
# inference) to verify test selection behavior for:
#   - Inference-only modifications (no runtime coverage)
#   - Mixed coverage + inference (no double-counting)
#   - No inference data (graceful degradation to coverage-only)
#
# See testimonial-1udj

using Testimonial
using Test

# ── Helpers ───────────────────────────────────

"""Build a CoverageIndex with runtime_edges and/or inference_edges."""
function _make_integration_index(
    items::Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage},
    runtime_edges::Dict{Testimonial.TestItemRef, Vector{Tuple{String, Int}}},
    infer_edges::Dict{Testimonial.TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}
)
    return Testimonial.CoverageIndex(
        items,
        "abc1234",
        string(VERSION),
        v"0.1.0",
        now(),
        "",
        Dict{String, Set{String}}(),
        runtime_edges,
        infer_edges,
        Testimonial._EMPTY_STATIC_EDGES,
        Testimonial._EMPTY_LAYER_DATA,
        0, 0, 1,
    )
end

"""Full provider list for integration tests."""
function _all_providers()
    return [
        Testimonial.runtime_edge_provider,
        Testimonial.inference_provider,
    ]
end

# ── Inference-only modification ──────────────

@testset "inference-only: test selected via inference when no runtime edge" begin
    # Test A has runtime_edges pointing to src/foo.jl
    # Test B has inference_edges pointing to src/lib.jl (no runtime_edges for it)
    # When src/lib.jl changes, only Test B should be selected (via inference)
    # When src/foo.jl changes, only Test A should be selected (via runtime edge)

    test_a_ref = Testimonial.TestItemRef("test/a_test.jl", 1, "test_a")
    test_b_ref = Testimonial.TestItemRef("test/b_test.jl", 1, "test_b")

    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(
        test_a_ref => Testimonial.ItemCoverage(test_a_ref, [1, 2, 3], Int[], Dict()),
        test_b_ref => Testimonial.ItemCoverage(test_b_ref, [4, 5, 6], Int[], Dict()),
    )

    runtime_edges = Dict{Testimonial.TestItemRef, Vector{Tuple{String, Int}}}(
        test_a_ref => [("src/foo.jl", 1)],
    )

    infer_edges = Dict{Testimonial.TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(
        test_b_ref => [("f", "src/lib.jl", 42, "g", "src/helper.jl", 10)],
    )

    index = _make_integration_index(items, runtime_edges, infer_edges)

    # When src/lib.jl changes → only test_b (inference-only) is selected
    changed_lib = Dict{String, Set{Int}}("src/lib.jl" => Set([42, 43]))
    results = Testimonial.query(_all_providers(), index, changed_lib)
    selected = [r for r in results if r.selected]
    @test length(selected) == 1
    @test selected[1].item.name == "test_b"

    # When src/foo.jl changes → only test_a (runtime edge) is selected
    changed_foo = Dict{String, Set{Int}}("src/foo.jl" => Set([1, 2]))
    results = Testimonial.query(_all_providers(), index, changed_foo)
    selected = [r for r in results if r.selected]
    @test length(selected) == 1
    @test selected[1].item.name == "test_a"
end

# ── Mixed coverage + inference ────────────────

@testset "mixed: runtime and inference edges for same file selects once" begin
    # Test A has BOTH runtime_edges AND inference_edges for src/lib.jl
    # When src/lib.jl changes, Test A should be selected exactly once
    # (no duplicate items in result) but with reasons from both providers

    test_a_ref = Testimonial.TestItemRef("test/a_test.jl", 1, "test_a")

    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(
        test_a_ref => Testimonial.ItemCoverage(test_a_ref, [1, 2, 3], Int[], Dict()),
    )

    runtime_edges = Dict{Testimonial.TestItemRef, Vector{Tuple{String, Int}}}(
        test_a_ref => [("src/lib.jl", 42)],
    )

    infer_edges = Dict{Testimonial.TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(
        test_a_ref => [("f", "src/lib.jl", 42, "g", "src/helper.jl", 10)],
    )

    index = _make_integration_index(items, runtime_edges, infer_edges)

    changed = Dict{String, Set{Int}}("src/lib.jl" => Set([42, 43]))
    results = Testimonial.query(_all_providers(), index, changed)
    selected = [r for r in results if r.selected]

    # Should select test_a exactly once (no duplicate entries)
    @test length(selected) == 1
    @test selected[1].item.name == "test_a"

    # Should have reasons from both providers (AlwaysRun from runtime edge, AlwaysRun from inference)
    @test length(selected[1].reasons) >= 2
end

# ── No inference data ─────────────────────────

@testset "no inference: falls back to runtime-edge-only" begin
    # Test A has runtime_edges for src/foo.jl, no inference_edges
    # When src/foo.jl changes, Test A is selected via runtime edge
    # When src/lib.jl changes, no tests are selected

    test_a_ref = Testimonial.TestItemRef("test/a_test.jl", 1, "test_a")

    items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(
        test_a_ref => Testimonial.ItemCoverage(test_a_ref, [1, 2, 3], Int[], Dict()),
    )

    runtime_edges = Dict{Testimonial.TestItemRef, Vector{Tuple{String, Int}}}(
        test_a_ref => [("src/foo.jl", 1), ("src/foo.jl", 2)],
    )

    index = _make_integration_index(
        items,
        runtime_edges,
        Dict{Testimonial.TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(),
    )

    # src/foo.jl changes → test_a selected via runtime edge
    changed_foo = Dict{String, Set{Int}}("src/foo.jl" => Set([1, 2]))
    results = Testimonial.query(_all_providers(), index, changed_foo)
    selected = [r for r in results if r.selected]
    @test length(selected) == 1
    @test selected[1].item.name == "test_a"

    # src/lib.jl changes → no tests selected
    changed_lib = Dict{String, Set{Int}}("src/lib.jl" => Set([42]))
    results = Testimonial.query(_all_providers(), index, changed_lib)
    selected = [r for r in results if r.selected]
    @test isempty(selected)
end