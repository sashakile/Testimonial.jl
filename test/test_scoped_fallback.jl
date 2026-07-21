# Testimonial.jl — Tests for scoped fallback behavior
#
# Verifies that scoped fallback degrades to global fallback before
# component boundary is deployed, and that fallback reasons are
# properly reported.
#
# See testimonial-3vo, testimonial-z9z in
# openspec/changes/add-safety-invariants/

using Testimonial
using Test

@testset "scoped_fallback degrades to global before component boundary" begin
    # Before component boundary: scoped = global
    result = Testimonial.scoped_fallback(
        ["unresolved file: src/lib.jl"],
        :no_component_boundary,
    )

    @test result == :full_suite
end

@testset "scoped_fallback returns full_suite for any fallback reason" begin
    reasons = ["unresolved file: src/lib.jl"]
    result = Testimonial.scoped_fallback(reasons, :no_component_boundary)
    @test result == :full_suite
end

@testset "scoped_fallback returns nothing for empty reasons" begin
    result = Testimonial.scoped_fallback(String[], :no_component_boundary)
    @test result === nothing
end

@testset "scoped_fallback collects fallback_reasons from ImpactResults" begin
    ref = TestItemRef("test/foo.jl", 1, "test_a")
    result = ImpactResult(ref, [ImpactReason(Unresolved, "not tracked")], false, "unresolved file: src/lib.jl")

    reasons = Testimonial.collect_fallback_reasons([result])
    @test length(reasons) == 1
    @test reasons[1] == "unresolved file: src/lib.jl"
end

@testset "collect_fallback_reasons skips results without fallback" begin
    ref = TestItemRef("test/foo.jl", 1, "test_a")
    result = ImpactResult(ref, [ImpactReason(DirectChange, "changed")], true)

    reasons = Testimonial.collect_fallback_reasons([result])
    @test isempty(reasons)
end

@testset "collect_fallback_reasons handles empty results" begin
    reasons = Testimonial.collect_fallback_reasons(ImpactResult[])
    @test isempty(reasons)
end

@testset "collect_fallback_reasons handles multiple fallback reasons" begin
    ref1 = TestItemRef("test/a.jl", 1, "test_a")
    ref2 = TestItemRef("test/b.jl", 1, "test_b")

    r1 = ImpactResult(ref1, [ImpactReason(Unresolved, "not tracked")], false, "unresolved file: src/a.jl")
    r2 = ImpactResult(ref2, [ImpactReason(Unresolved, "not tracked")], false, "unresolved file: src/b.jl")

    reasons = Testimonial.collect_fallback_reasons([r1, r2])
    @test length(reasons) == 2
end

@testset "scoped_fallback accepts component_mode" begin
    # With component boundary mode, scoped would be per-component
    # But before boundary exists, it's still global
    result = Testimonial.scoped_fallback(
        ["unresolved file: src/lib.jl"],
        :per_component,
    )

    # For now: per_component also degrades to global
    @test result == :full_suite
end