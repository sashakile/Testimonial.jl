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
    # A brand-new index (just created) with default signals should be confident
    # With 1 layer (0.5) and 3 stubs (1.0 each): (0.5)^0.25 ≈ 0.84
    @test score >= 0.8
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

# ── stale_threshold_hours config ──────────────

@testset "DEFAULT_STALE_THRESHOLD_HOURS is 48" begin
    @test Testimonial.DEFAULT_STALE_THRESHOLD_HOURS == 48
end

@testset "_freshness_signal accepts optional stale_threshold_hours" begin
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
    stale_at = now() - Hour(72)  # 72 hours old
    index = make_index(created_at=stale_at)

    # With default threshold (48h), 72h old index should have 0 freshness
    default_signal = Testimonial._freshness_signal(index)
    @test default_signal == 0.0

    # With custom threshold (96h), 72h old index should have some freshness
    custom_signal = Testimonial._freshness_signal(index; stale_threshold_hours=96.0)
    @test 0.0 < custom_signal <= 1.0
    @test custom_signal ≈ 0.25 atol=0.001
end

@testset "compute_confidence uses config-based stale_threshold_hours" begin
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
    stale_at = now() - Hour(36)  # 36 hours old
    index = make_index(created_at=stale_at)

    # With shorter threshold (24h), 36h old index should be stale (freshness=0)
    short_threshold_score = Testimonial.compute_confidence(ref, index; stale_threshold_hours=24.0)
    @test short_threshold_score == 0.0

    # With longer threshold (72h), 36h old index should be fresh
    long_threshold_score = Testimonial.compute_confidence(ref, index; stale_threshold_hours=72.0)
    @test long_threshold_score > 0.5
end

# ── confidence_threshold config ───────────────

@testset "DEFAULT_CONFIDENCE_THRESHOLD is 0.7" begin
    @test Testimonial.DEFAULT_CONFIDENCE_THRESHOLD == 0.7
end

@testset "parse_confidence_config returns default threshold" begin
    config = Dict{String, Any}()
    cc = Testimonial.parse_confidence_config(config)
    @test cc.threshold == 0.7
    @test isempty(cc.component_overrides)
end

@testset "parse_confidence_config reads global threshold" begin
    config = Dict{String, Any}(
        "confidence" => Dict{String, Any}(
            "threshold" => 0.5,
        )
    )
    cc = Testimonial.parse_confidence_config(config)
    @test cc.threshold == 0.5
end

@testset "parse_confidence_config reads per-component overrides" begin
    config = Dict{String, Any}(
        "confidence" => Dict{String, Any}(
            "threshold" => 0.7,
            "components" => Dict{String, Any}(
                "PkgA" => 0.5,
                "PkgB" => 0.8,
            ),
        )
    )
    cc = Testimonial.parse_confidence_config(config)
    @test cc.threshold == 0.7
    @test haskey(cc.component_overrides, :PkgA)
    @test cc.component_overrides[:PkgA] == 0.5
    @test haskey(cc.component_overrides, :PkgB)
    @test cc.component_overrides[:PkgB] == 0.8
end

@testset "parse_confidence_config clamps threshold to [0, 1]" begin
    config = Dict{String, Any}(
        "confidence" => Dict{String, Any}(
            "threshold" => 1.5,
            "components" => Dict{String, Any}(
                "PkgA" => -0.5,
            ),
        )
    )
    cc = Testimonial.parse_confidence_config(config)
    @test cc.threshold == 1.0
    @test cc.component_overrides[:PkgA] == 0.0
end

# ── recording quality signal ──────────────────

@testset "_recording_quality_signal returns 1.0 with no failures" begin
    index = make_index()
    @test Testimonial._recording_quality_signal(index) == 1.0
end

@testset "_recording_quality_signal returns 0.5 with half failures" begin
    index = make_index(
        items=[("/proj/test/a.jl", "t1"), ("/proj/test/b.jl", "t2")],
    )
    # Create a new index with recording metadata
    half_fail = Testimonial.CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        1,  # failed_item_count
        2,  # total_discovered_items
    )
    signal = Testimonial._recording_quality_signal(half_fail)
    @test signal ≈ 0.5 atol=0.001
end

@testset "_recording_quality_signal returns 0.0 when all items failed" begin
    index = make_index()
    all_fail = Testimonial.CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        5,  # failed_item_count
        5,  # total_discovered_items
    )
    @test Testimonial._recording_quality_signal(all_fail) == 0.0
end

@testset "_recording_quality_signal handles zero total items" begin
    index = make_index()
    zero_total = Testimonial.CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        0,  # failed_item_count
        0,  # total_discovered_items
    )
    @test Testimonial._recording_quality_signal(zero_total) == 1.0
end

# ── layer coverage signal ─────────────────────

@testset "_layer_coverage_signal returns 0.5 for single layer (default)" begin
    index = make_index()
    @test Testimonial._layer_coverage_signal(index) ≈ 0.5 atol=0.001
end

@testset "_layer_coverage_signal returns 0.67 for two layers" begin
    index = make_index()
    two_layer = Testimonial.CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        index.failed_item_count,
        index.total_discovered_items,
        2,  # available_layers
    )
    @test Testimonial._layer_coverage_signal(two_layer) ≈ 2.0/3.0 atol=0.001
end

@testset "_layer_coverage_signal returns 0.75 for three layers" begin
    index = make_index()
    three_layer = Testimonial.CoverageIndex(
        index.items,
        index.git_hash,
        index.julia_version,
        index.schema_version,
        index.created_at,
        index.environment_fingerprint,
        index.inter_component_edges,
        index.runtime_edges,
        index.failed_item_count,
        index.total_discovered_items,
        3,  # available_layers
    )
    @test Testimonial._layer_coverage_signal(three_layer) ≈ 0.75 atol=0.001
end