# Testimonial.jl — Tests for ImpactReason.chain field (PROV-001)
#
# Adds an optional reason chain to ImpactReason. See ticket testimonial-21p6
# and openspec/changes/add-provenance-explainability/specs/provenance/spec.md.

using Testimonial
using Test

@testset "ImpactReason has a chain::Vector{ProvenanceLink} field" begin
    r = ImpactReason(DirectChange, "file changed: src/foo.jl")
    @test hasproperty(r, :chain)
    @test r.chain isa Vector{ProvenanceLink}
    # Default-constructed chain is empty
    @test isempty(r.chain)
end

@testset "ImpactReason accepts an explicit chain (3-arg constructor)" begin
    link = ProvenanceLink(COVERAGE, "src/bs.jl:47", "executed line 47", nothing)
    r = ImpactReason(DirectChange, "covered line changed", [link])
    @test length(r.chain) == 1
    @test r.chain[1].layer == COVERAGE
    @test r.chain[1].content_unit == "src/bs.jl:47"
end

@testset "2-arg ImpactReason constructor backward-compat (empty chain)" begin
    # Existing call sites must keep working.
    r = ImpactReason(AlwaysRun, "always-run: test has recent failures")
    @test r.kind == AlwaysRun
    @test r.description == "always-run: test has recent failures"
    @test isempty(r.chain)
end

@testset "ImpactReason equality is structural including chain" begin
    link = ProvenanceLink(STATIC, "foo()", "method foo", nothing)
    a = ImpactReason(DirectChange, "d", [link])
    b = ImpactReason(DirectChange, "d", [link])
    c = ImpactReason(DirectChange, "d", ProvenanceLink[])  # empty chain
    @test a == b
    @test a != c
end

@testset "ImpactResult carrying a chained reason round-trips" begin
    link = ProvenanceLink(COVERAGE, "src/x.jl:10", "executed line 10", nothing)
    reason = ImpactReason(DirectChange, "covered line changed", [link])
    ref = TestItemRef("/proj/test/t.jl", 1, "t")
    result = ImpactResult(ref, [reason])
    @test result.selected
    @test length(result.reasons) == 1
    @test length(result.reasons[1].chain) == 1
    @test result.reasons[1].chain[1].next === nothing
end
