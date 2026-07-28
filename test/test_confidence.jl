# Testimonial.jl — Tests for confidence scoring
#
# Tests the compute_confidence function and its constituent signals.
#
# See testimonial-n6ky — Implement compute_confidence(test_ref, index) function
# in openspec/changes/add-confidence-scoring/tasks.md

using Testimonial
using Test
using Dates

# ── Helpers ───────────────────────────────────

"""Create a CoverageIndex with mock items for testing."""
function make_index(;
    items::Vector{Tuple{String, String}}=Tuple{String, String}[],
    created_at::DateTime=now(),
    git_hash::String="abc1234",
)
    item_dict = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}()
    for (file, name) in items
        ref = Testimonial.TestItemRef(file, 1, name)
        item_dict[ref] = Testimonial.ItemCoverage(ref, Int[], Int[], Dict())
    end
    return Testimonial.CoverageIndex(
        item_dict,
        git_hash,
        string(VERSION),
        v"0.1.0",
        created_at,
    )
end

# ── compute_confidence — basic structure ──────

@testset "compute_confidence returns 1.0 for a fresh index with default parameters" begin
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
    index = make_index(items=[("/proj/test/foo_test.jl", "test_a")])

    score = Testimonial.compute_confidence(ref, index)

    @test 0.0 <= score <= 1.0
    # A brand-new index (just created) with default signals should be highly confident
    @test score >= 0.9
end

@testset "compute_confidence returns a Float64 in [0, 1]" begin
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
    index = make_index()

    score = Testimonial.compute_confidence(ref, index)

    @test score isa Float64
    @test 0.0 <= score <= 1.0
end

@testset "compute_confidence handles test items not in the index" begin
    ref = Testimonial.TestItemRef("/proj/test/unknown.jl", 1, "ghost_test")
    index = make_index(items=[("/proj/test/foo_test.jl", "test_a")])

    # Should not throw; gracefully handle items not found in index
    score = Testimonial.compute_confidence(ref, index)

    @test score isa Float64
    @test 0.0 <= score <= 1.0
end

@testset "compute_confidence degrades with stale index" begin
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
    stale_at = now() - Day(3)  # 72 hours old
    index = make_index(
        items=[("/proj/test/foo_test.jl", "test_a")],
        created_at=stale_at,
    )

    score = Testimonial.compute_confidence(ref, index)

    # A stale index should have lower confidence
    @test 0.0 <= score <= 1.0
    @test score < 0.5
end

@testset "compute_confidence returns 0.0 for extremely stale index" begin
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
    very_stale_at = now() - Day(60)  # 60 days old
    index = make_index(
        items=[("/proj/test/foo_test.jl", "test_a")],
        created_at=very_stale_at,
    )

    score = Testimonial.compute_confidence(ref, index)

    @test score == 0.0
end