# Testimonial.jl — Tests for TestimonialRunner environment (scripts/TestimonialRunner/)
#
# Verifies the subprocess runner workspace is properly set up with the
# correct dependencies for isolated @testitem recording.
#
# See REC-009 in openspec/changes/implement-coverage-layer/specs/recording/spec.md

using Testimonial
using Test

# ── Runner Project.toml ────────────────────────

@testset "TestimonialRunner Project.toml exists" begin
    path = joinpath(@__DIR__, "..", "scripts", "TestimonialRunner", "Project.toml")
    @test isfile(path)
end

@testset "TestimonialRunner Project.toml has required deps" begin
    path = joinpath(@__DIR__, "..", "scripts", "TestimonialRunner", "Project.toml")
    content = try
        read(path, String)
    catch
        @test false
        return
    end

    # Check for the three required dependency entries
    found_testimonial = !isnothing(findfirst("Testimonial", content))
    found_retest = !isnothing(findfirst("ReTestItems", content))
    found_coverage = !isnothing(findfirst("Coverage", content))
    @test found_testimonial
    @test found_retest
    @test found_coverage
end