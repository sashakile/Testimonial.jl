# Testimonial.jl — Tests for ProvenanceLink + LayerKind (PROV-001 foundation)
#
# Defines the immutable reason-chain link type used by the Provenance &
# Explainability epic. See ticket testimonial-tgm3 and
# openspec/changes/add-provenance-explainability/specs/provenance/spec.md.

using Testimonial
using Test

# ── LayerKind enum ────────────────────────────

@testset "LayerKind enum has the five spec layers" begin
    @test COVERAGE isa LayerKind
    @test INFERRED isa LayerKind
    @test STATIC isa LayerKind
    @test TEST_FILE_CHANGED isa LayerKind
    @test MANUAL isa LayerKind
    # No extra variants
    @test length(instances(LayerKind)) == 5
end

# ── ProvenanceLink struct ──────────────────────

@testset "ProvenanceLink has the four spec fields" begin
    link = ProvenanceLink(
        COVERAGE,
        "src/bs.jl:47",
        "executed line 47 in bs.jl",
        nothing,
    )
    @test link.layer == COVERAGE
    @test link.content_unit == "src/bs.jl:47"
    @test link.detail == "executed line 47 in bs.jl"
    @test link.next === nothing
end

@testset "ProvenanceLink forms a linked list via next" begin
    tail = ProvenanceLink(STATIC, "foo()", "method foo called", nothing)
    head = ProvenanceLink(INFERRED, "bar()", "calls foo()", tail)
    @test head.next === tail
    @test head.next.next === nothing
    # Chain is two links deep
    @test head.next.layer == STATIC
end

@testset "ProvenanceLink is immutable and equality is structural" begin
    a = ProvenanceLink(COVERAGE, "f:1", "d", nothing)
    b = ProvenanceLink(COVERAGE, "f:1", "d", nothing)
    @test a == b
    @test_throws ErrorException a.layer = STATIC
end
