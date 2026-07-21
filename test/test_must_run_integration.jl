# Testimonial.jl — Integration tests for must-run + fallback pipeline
#
# Exercises the full pipeline: must_run_with_fallback_priority →
# must_run_provider → query with real CoverageIndex.
#
# See EXCL-003 in rule-of-5 review

using Testimonial
using Test
using Dates

@testset "must_run integration: full pipeline without fallback" begin
    rules = [MustRunRule("src/critical/*.jl", :critical)]
    changed_files = ["src/critical/payment.jl"]
    fallback_reasons = String[]

    # Step 1: priority check
    priority = Testimonial.must_run_with_fallback_priority(rules, changed_files, fallback_reasons)
    @test priority == :must_run

    # Step 2: build index with tagged and untagged items
    ref_critical = TestItemRef("test/critical_test.jl", 10, "test_critical", [:critical], "abc")
    ref_other = TestItemRef("test/other_test.jl", 5, "test_other", [:other], "def")
    items = Dict{TestItemRef, ItemCoverage}(
        ref_critical => ItemCoverage(ref_critical, [1, 2], Int[], Dict()),
        ref_other => ItemCoverage(ref_other, [3, 4], Int[], Dict()),
    )
    index = CoverageIndex(items, "abc", string(VERSION), v"0.1.0", now())

    # Step 3: run must_run_provider
    providers = [
        (idx, files; kw...) -> Testimonial.must_run_provider(idx, files; must_run_rules=rules, kw...),
        Testimonial.direct_change_provider,
    ]
    changed = Dict("src/critical/payment.jl" => Set([1, 2, 3]))
    results = Testimonial.query(providers, index, changed)

    # Step 4: verify
    @test !isempty(results)
    must_run = filter(r -> r.item.name == "test_critical", results)
    @test !isempty(must_run)
    @test must_run[1].selected == true
end

@testset "must_run integration: full pipeline with fallback" begin
    rules = [MustRunRule("src/critical/*.jl", :critical)]
    changed_files = ["src/critical/payment.jl"]
    fallback_reasons = ["unresolved file: src/lib.jl"]

    # Step 1: priority check — fallback wins
    priority = Testimonial.must_run_with_fallback_priority(rules, changed_files, fallback_reasons)
    @test priority == :fallback

    # Step 2: no must-run provider needed, but scoped_fallback confirms
    result = Testimonial.scoped_fallback(fallback_reasons)
    @test result == :full_suite
end

@testset "must_run integration: empty rules and no fallback" begin
    priority = Testimonial.must_run_with_fallback_priority(MustRunRule[], String[], String[])
    @test priority === nothing

    result = Testimonial.scoped_fallback(String[])
    @test result === nothing
end