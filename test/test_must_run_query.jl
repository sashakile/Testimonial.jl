# Testimonial.jl — Tests for must-run rule application in query
#
# Verifies that must-run rules force-select tests with matching tags
# when changed files match the rules' glob patterns.
#
# See testimonial-hgy in openspec/changes/add-safety-invariants/

using Testimonial
using Test
using Dates

@testset "must_run_provider returns AlwaysRun for matched tag" begin
    rules = [MustRunRule("src/critical/*.jl", :critical)]
    changed_files = ["src/critical/payment.jl"]

    # Build index with test items tagged :critical and :other
    ref_critical = TestItemRef("test/critical_test.jl", 10, "test_critical", [:critical], "abc")
    ref_other = TestItemRef("test/other_test.jl", 5, "test_other", [:other], "def")
    items = Dict{TestItemRef, ItemCoverage}(
        ref_critical => ItemCoverage(ref_critical, [1, 2], Int[], Dict()),
        ref_other => ItemCoverage(ref_other, [3, 4], Int[], Dict()),
    )
    index = CoverageIndex(items, "abc", string(VERSION), v"0.1.0", now())

    results = Testimonial.must_run_provider(index, changed_files; must_run_rules=rules)

    @test length(results) == 1
    @test results[1].item.name == "test_critical"
    @test results[1].selected == true
    @test results[1].reasons[1].kind == Testimonial.AlwaysRun
    @test occursin("must-run rule", results[1].reasons[1].description)
end

@testset "must_run_provider returns empty when no rules match" begin
    rules = [MustRunRule("src/other/*.jl", :critical)]
    changed_files = ["src/critical/payment.jl"]

    ref = TestItemRef("test/critical_test.jl", 10, "test_critical", [:critical], "abc")
    items = Dict{TestItemRef, ItemCoverage}(
        ref => ItemCoverage(ref, [1, 2], Int[], Dict()),
    )
    index = CoverageIndex(items, "abc", string(VERSION), v"0.1.0", now())

    results = Testimonial.must_run_provider(index, changed_files; must_run_rules=rules)
    @test isempty(results)
end

@testset "must_run_provider returns empty when no rules defined" begin
    changed_files = ["src/critical/payment.jl"]
    ref = TestItemRef("test/critical_test.jl", 10, "test_critical", [:critical], "abc")
    items = Dict{TestItemRef, ItemCoverage}(
        ref => ItemCoverage(ref, [1, 2], Int[], Dict()),
    )
    index = CoverageIndex(items, "abc", string(VERSION), v"0.1.0", now())

    results = Testimonial.must_run_provider(index, changed_files; must_run_rules=MustRunRule[])
    @test isempty(results)
end

@testset "must_run_provider integrates with query" begin
    rules = [MustRunRule("src/critical/*.jl", :critical)]
    changed = Dict("src/critical/payment.jl" => Set([1, 2, 3]))

    ref_critical = TestItemRef("test/critical_test.jl", 10, "test_critical", [:critical], "abc")
    items = Dict{TestItemRef, ItemCoverage}(
        ref_critical => ItemCoverage(ref_critical, [1, 2], Int[], Dict()),
    )
    index = CoverageIndex(items, "abc", string(VERSION), v"0.1.0", now())

    providers = [
        (idx, files) -> Testimonial.must_run_provider(idx, files; must_run_rules=rules),
        Testimonial.direct_change_provider,
    ]

    results = Testimonial.query(providers, index, changed)

    @test !isempty(results)
    # Test tagged :critical was selected by must-run rule
    must_run = filter(r -> r.item.name == "test_critical", results)
    @test !isempty(must_run)
    @test must_run[1].selected == true
end