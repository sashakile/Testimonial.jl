# Testimonial.jl — Tests for must-run + scoped-fallback priority
#
# Verifies that scoped fallback takes priority over must-run rules:
# if a component falls back to full suite, must-run is not needed.
# If no fallback, must-run rules force-select tests.
#
# See testimonial-0on in openspec/changes/add-safety-invariants/

using Testimonial
using Test

@testset "must_run_priority: no fallback => must-run applies" begin
    rules = [MustRunRule("src/critical/*.jl", :critical)]
    changed_files = ["src/critical/payment.jl"]
    fallback_reasons = String[]

    result = Testimonial.must_run_with_fallback_priority(
        rules, changed_files, fallback_reasons
    )

    @test result == :must_run
end

@testset "must_run_priority: fallback => must-run suppressed" begin
    rules = [MustRunRule("src/critical/*.jl", :critical)]
    changed_files = ["src/critical/payment.jl"]
    fallback_reasons = ["unresolved file: src/lib.jl"]

    result = Testimonial.must_run_with_fallback_priority(
        rules, changed_files, fallback_reasons
    )

    @test result == :fallback
end

@testset "must_run_priority: no rules and no fallback => nothing" begin
    result = Testimonial.must_run_with_fallback_priority(
        MustRunRule[], String[], String[]
    )

    @test result === nothing
end

@testset "must_run_priority: no rules but fallback => fallback" begin
    result = Testimonial.must_run_with_fallback_priority(
        MustRunRule[], String[], ["unresolved file"]
    )

    @test result == :fallback
end

@testset "must_run_priority: rules but no matching files => nothing" begin
    rules = [MustRunRule("src/critical/*.jl", :critical)]
    result = Testimonial.must_run_with_fallback_priority(
        rules, String[], String[]
    )

    @test result === nothing
end