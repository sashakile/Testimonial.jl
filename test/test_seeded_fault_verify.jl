# Testimonial.jl — Tests for seeded fault verification
#
# Verifies that for each seed pattern, the fault-revealing test
# is selected after injecting a known semantic mutation.
#
# See testimonial-0zm in openspec/changes/add-safety-invariants/

using Testimonial
using Test

@testset "run_seeded_fault_test returns correct structure" begin
    pattern = Testimonial.SEED_FAULT_PATTERNS[1]
    result = Testimonial.run_seeded_fault_test(pattern)

    @test haskey(result, :pattern_name)
    @test haskey(result, :passed)
    @test haskey(result, :selected_items)
    @test haskey(result, :error)
    @test result[:pattern_name] == pattern.name
end

@testset "run_seeded_fault_test handles invalid pattern" begin
    invalid = (name = "invalid", description = "", action = "", revealing_test = "")
    result = Testimonial.run_seeded_fault_test(invalid)
    @test result[:passed] == false
    @test !isempty(result[:error])
end

@testset "run_all_seeded_fault_tests runs all patterns" begin
    results = Testimonial.run_all_seeded_fault_tests()

    @test length(results) == length(Testimonial.SEED_FAULT_PATTERNS)
    for r in results
        @test haskey(r, :pattern_name)
        @test haskey(r, :passed)
    end
end

@testset "run_all_seeded_fault_tests returns non-empty results" begin
    results = Testimonial.run_all_seeded_fault_tests()
    @test !isempty(results)
end

@testset "run_all_seeded_fault_tests aggregate pass/fail" begin
    results = Testimonial.run_all_seeded_fault_tests()
    all_passed = all(r[:passed] for r in results)
    @test all_passed == true
end

@testset "seed patterns have unique names" begin
    names = [p.name for p in Testimonial.SEED_FAULT_PATTERNS]
    @test length(names) == length(Set(names))
end

@testset "seed patterns have non-empty action" begin
    for pattern in Testimonial.SEED_FAULT_PATTERNS
        @test !isempty(strip(get(pattern, :action, "")))
    end
end

@testset "seeded fault script exists" begin
    script = joinpath(@__DIR__, "..", "scripts", "seeded_fault_test.jl")
    @test isfile(script)
end