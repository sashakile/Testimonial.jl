# Testimonial.jl — Tests for explain(exclude=true) exclusion reasoning (PROV-002)
#
# Adds an exclusion mode to `explain` that reports why a test was NOT
# selected. See ticket testimonial-99rk and
# openspec/changes/add-provenance-explainability/specs/provenance/spec.md.

using Testimonial
using Test
using Dates: now

# ── Helpers ───────────────────────────────────

"""Build a CoverageIndex with one item covering src/foo.jl lines [10,20]."""
function _exclude_index(;
    test_file::String="/proj/test/foo_test.jl",
    item_name::String="test_a",
    src_file::String="/proj/src/foo.jl",
    covered_lines::Vector{Int}=[10, 20],
    component::String="",
)
    ref = TestItemRef(test_file, 1, item_name, Symbol[], "h1", nothing, component, String[])
    source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
        src_file => (covered_lines, Int[]),
    )
    ic = ItemCoverage(ref, Int[], Int[], source_files)
    items = Dict{TestItemRef, ItemCoverage}(ref => ic)
    return CoverageIndex(items, "sha", "1.12", v"0.1.0", now())
end

# ── Scenario: test not in index ───────────────

@testset "explain(exclude=true): test not in index → 'never recorded'" begin
    index = _exclude_index()
    changed = Dict{String, Set{Int}}("/proj/src/foo.jl" => Set([10]))

    out = explain("/proj/test/foo_test.jl", "brand_new_test";
                  exclude=true, changed=changed, index=index)

    @test out isa Vector{String}
    @test !isempty(out)
    @test any(contains(l, "never been recorded") for l in out)
    @test any(contains(l, "record_all") for l in out)
end

# ── Scenario: no coverage overlap ─────────────

@testset "explain(exclude=true): no coverage overlap lists covered + changed files" begin
    index = _exclude_index(covered_lines=[10, 20])
    # Changed file is a DIFFERENT file the test doesn't cover
    changed = Dict{String, Set{Int}}("/proj/src/other.jl" => Set([1, 2]))

    out = explain("/proj/test/foo_test.jl", "test_a";
                  exclude=true, changed=changed, index=index)

    @test !isempty(out)
    @test any(contains(l, "no changed file touches any covered line") for l in out)
    # Lists the files the test covers
    @test any(contains(l, "foo.jl") for l in out)
    # Lists the changed files
    @test any(contains(l, "other.jl") for l in out)
end

@testset "explain(exclude=true): coverage overlap means NOT excluded (selected)" begin
    index = _exclude_index(covered_lines=[10, 20])
    # Changed line 10 overlaps the test's coverage
    changed = Dict{String, Set{Int}}("/proj/src/foo.jl" => Set([10]))

    out = explain("/proj/test/foo_test.jl", "test_a";
                  exclude=true, changed=changed, index=index)

    # When the test WOULD be selected, exclude mode says so.
    @test !isempty(out)
    @test any(contains(l, "selected") || contains(l, "not excluded") for l in out)
end

# ── Scenario: different component ─────────────

@testset "explain(exclude=true): different component → no dependency path" begin
    # Test is in component B; changed file is in component A's src dir.
    index = _exclude_index(
        test_file="/proj/comp_b/test/foo_test.jl",
        src_file="/proj/comp_b/src/foo.jl",
        covered_lines=[10],
        component="comp_b",
    )
    changed = Dict{String, Set{Int}}("/proj/comp_a/src/x.jl" => Set([1]))

    out = explain("/proj/comp_b/test/foo_test.jl", "test_a";
                  exclude=true, changed=changed, index=index)

    @test !isempty(out)
    @test any(contains(l, "no dependency path") || contains(l, "different component") for l in out)
end

# ── Backward compat: exclude=false (default) ──

@testset "explain without exclude= stays on the covered-files path" begin
    index = _exclude_index(covered_lines=[10, 20])
    out = explain("/proj/test/foo_test.jl", "test_a"; index=index)
    @test out isa Vector{String}
    # Original behaviour: mentions the test file + covered count
    @test any(contains(l, "foo_test.jl") || contains(l, "foo.jl") for l in out)
end


# ── Edge cases ────────────────────────────────

@testset "explain(exclude=true): empty changed set → meaningful message" begin
    index = _exclude_index()
    out = explain("/proj/test/foo_test.jl", "test_a";
                  exclude=true, changed=Dict{String,Set{Int}}(), index=index)
    @test !isempty(out)
    @test any(contains(l, "no change") || contains(l, "no diff") ||
              contains(l, "empty") for l in out)
end

@testset "explain(exclude=true): test with no component skips component check" begin
    # component="" is the default; must not error or produce a comp-related msg.
    index = _exclude_index(component="")
    changed = Dict{String, Set{Int}}("/proj/src/other.jl" => Set([1]))
    out = explain("/proj/test/foo_test.jl", "test_a";
                  exclude=true, changed=changed, index=index)
    @test !isempty(out)
    # Should NOT mention component in the output.
    @test all(!contains(l, "component") for l in out)
end

@testset "explain(exclude=true): test with empty source_files → no coverage data" begin
    ref = TestItemRef("/proj/test/empty_test.jl", 1, "test_e")
    ic = ItemCoverage(ref, Int[], Int[], Dict{String,Tuple{Vector{Int},Vector{Int}}}())
    index = CoverageIndex(Dict(ref => ic), "sha", "1.12", v"0.1.0", now())
    changed = Dict{String, Set{Int}}("/proj/src/x.jl" => Set([1]))
    out = explain("/proj/test/empty_test.jl", "test_e";
                  exclude=true, changed=changed, index=index)
    @test !isempty(out)
    @test any(contains(l, "no coverage") || contains(l, "no changed file") for l in out)
end
