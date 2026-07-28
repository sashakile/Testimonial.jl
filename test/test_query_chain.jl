# Testimonial.jl — Tests for reason-chain building during query (PROV-001)
#
# Populates ImpactReason.chain for the coverage and test-file-changed paths.
# See ticket testimonial-l6p0 and
# openspec/changes/add-provenance-explainability/specs/provenance/spec.md.

using Testimonial
using Test
using Dates: now

# ── Helpers ───────────────────────────────────

"""Build a minimal CoverageIndex with one item covering specific source lines."""
function _index_with_coverage(;
    test_file::String="/proj/test/foo_test.jl",
    item_name::String="test_a",
    src_file::String="/proj/src/bs.jl",
    covered_lines::Vector{Int}=[47],
)
    ref = TestItemRef(test_file, 1, item_name)
    uncovered = Int[]
    source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
        src_file => (covered_lines, uncovered),
    )
    ic = ItemCoverage(ref, Int[], Int[], source_files)
    items = Dict{TestItemRef, ItemCoverage}(ref => ic)
    return CoverageIndex(items, "sha", "1.12", v"0.1.0", now())
end

# ── coverage_provider ─────────────────────────

@testset "coverage_provider traces a changed line to a covering test (COVERAGE chain)" begin
    # Spec scenario: changed line 47 in src/bs.jl is covered by the test.
    index = _index_with_coverage(covered_lines=[47])
    changed = Dict{String, Set{Int}}(
        "/proj/src/bs.jl" => Set([47]),
    )

    results = Testimonial.coverage_provider(changed)(index, ["/proj/src/bs.jl"])

    @test length(results) == 1
    r = results[1]
    @test r.selected
    @test length(r.reasons) == 1
    reason = r.reasons[1]
    @test length(reason.chain) == 1
    link = reason.chain[1]
    @test link.layer == COVERAGE
    @test link.content_unit == "/proj/src/bs.jl:47"
    @test link.next === nothing
    @test occursin("47", link.detail)
end

@testset "coverage_provider ignores changed lines the test does not cover" begin
    index = _index_with_coverage(covered_lines=[47])
    changed = Dict{String, Set{Int}}(
        "/proj/src/bs.jl" => Set([100]),  # line 100 not covered
    )

    results = Testimonial.coverage_provider(changed)(index, ["/proj/src/bs.jl"])
    @test isempty(results)
end

@testset "coverage_provider emits one chain link per covered changed line" begin
    index = _index_with_coverage(covered_lines=[10, 20, 30])
    changed = Dict{String, Set{Int}}(
        "/proj/src/bs.jl" => Set([10, 30, 99]),  # 99 not covered
    )

    results = Testimonial.coverage_provider(changed)(index, ["/proj/src/bs.jl"])
    @test length(results) == 1
    chain = results[1].reasons[1].chain
    @test length(chain) == 2  # only lines 10 and 30
    @test sort([l.content_unit for l in chain]) ==
        ["/proj/src/bs.jl:10", "/proj/src/bs.jl:30"]
end

@testset "coverage_provider skips changed files with no coverage data" begin
    index = _index_with_coverage()
    changed = Dict{String, Set{Int}}(
        "/proj/src/other.jl" => Set([1]),
    )

    results = Testimonial.coverage_provider(changed)(index, ["/proj/src/other.jl"])
    @test isempty(results)
end

# ── direct_change_provider chain ──────────────

@testset "direct_change_provider emits a TEST_FILE_CHANGED chain link" begin
    # When a test's own file changed, direct_change_provider selects it;
    # the chain should record the TEST_FILE_CHANGED layer.
    test_file = "/proj/test/foo_test.jl"
    index = _index_with_coverage()
    results = Testimonial.direct_change_provider(index, [test_file])

    @test length(results) == 1
    reason = results[1].reasons[1]
    @test length(reason.chain) == 1
    @test reason.chain[1].layer == TEST_FILE_CHANGED
    @test reason.chain[1].content_unit == test_file
    @test reason.chain[1].next === nothing
end
