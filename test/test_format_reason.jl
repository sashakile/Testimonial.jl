# Testimonial.jl — Tests for reason-chain display formatting (PROV-001, task 1.4)
#
# `format_reason` / `format_impact_result` render ImpactReasons (including
# their ProvenanceLink chains) as human-readable lines. These are the
# display building blocks for dry-run selection output.
#
# See ticket testimonial-q68n and
# openspec/changes/add-provenance-explainability/specs/provenance/spec.md.

using Testimonial
using Test

# ── format_reason ─────────────────────────────

@testset "format_reason renders kind + description for a chainless reason" begin
    r = ImpactReason(DirectChange, "file changed: src/foo.jl")
    lines = Testimonial.format_reason(r)
    @test lines isa Vector{String}
    @test !isempty(lines)
    @test contains(lines[1], "DirectChange")
    @test contains(lines[1], "file changed: src/foo.jl")
    # No chain → no indented link lines
    @test all(!contains(l, "└") for l in lines)
end

@testset "format_reason renders each chain link indented under the reason" begin
    link = ProvenanceLink(COVERAGE, "src/bs.jl:47", "executed line 47 in bs.jl", nothing)
    r = ImpactReason(DirectChange, "covered line(s) changed: 1", [link])
    lines = Testimonial.format_reason(r)
    # First line is the reason header; subsequent lines are chain links
    @test length(lines) == 2
    @test contains(lines[2], "COVERAGE")
    @test contains(lines[2], "src/bs.jl:47")
    @test contains(lines[2], "executed line 47 in bs.jl")
    # Chain link is indented to show nesting
    @test startswith(lines[2], " ") || startswith(lines[2], "\t")
end

@testset "format_reason renders a multi-link chain" begin
    tail = ProvenanceLink(STATIC, "foo()", "method foo called", nothing)
    head = ProvenanceLink(INFERRED, "bar()", "calls foo()", tail)
    r = ImpactReason(DependencyChange, "inferred edge", [head])
    lines = Testimonial.format_reason(r)
    # Header + 2 chain links
    @test length(lines) == 3
    @test contains(lines[2], "INFERRED")
    @test contains(lines[3], "STATIC")
end

# ── format_impact_result ──────────────────────

@testset "format_impact_result renders the item header + each reason" begin
    ref = TestItemRef("/proj/test/foo_test.jl", 10, "test_a")
    link = ProvenanceLink(COVERAGE, "/proj/src/x.jl:5", "executed line 5 in x.jl", nothing)
    r1 = ImpactReason(DirectChange, "covered line changed", [link])
    r2 = ImpactReason(AlwaysRun, "must-run rule", ProvenanceLink[])
    result = ImpactResult(ref, [r1, r2], true)

    lines = Testimonial.format_impact_result(result)
    @test !isempty(lines)
    # Header mentions the item name
    @test any(contains(l, "test_a") for l in lines)
    # Both reasons appear
    @test any(contains(l, "covered line changed") for l in lines)
    @test any(contains(l, "must-run rule") for l in lines)
    # The coverage chain link appears
    @test any(contains(l, "COVERAGE") for l in lines)
end

@testset "format_impact_result marks unselected results" begin
    ref = TestItemRef("/proj/test/foo_test.jl", 10, "test_x")
    r = ImpactReason(Unresolved, "not tracked", ProvenanceLink[])
    result = ImpactResult(ref, [r], false, "fallback: unresolved")
    lines = Testimonial.format_impact_result(result)
    @test any(contains(l, "test_x") for l in lines)
    # Unselected status surfaced
    @test any(contains(l, "not selected") || contains(l, "excluded") ||
              contains(l, "selected=false") for l in lines)
end

@testset "format_impact_result handles an empty reason list" begin
    ref = TestItemRef("/proj/test/foo_test.jl", 10, "test_y")
    result = ImpactResult(ref, ImpactReason[], false)
    lines = Testimonial.format_impact_result(result)
    @test !isempty(lines)
    @test any(contains(l, "test_y") for l in lines)
end
