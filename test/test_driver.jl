# Testimonial.jl — Tests for TestimonialRunner driver.jl
#
# Verifies the subprocess entry point script exists with the correct
# structure for running individual @testitems via ReTestItems.runtests.
#
# See REC-009 in openspec/changes/implement-coverage-layer/specs/recording/spec.md

using Testimonial
using Test

@testset "TestimonialRunner driver.jl exists" begin
    path = joinpath(@__DIR__, "..", "scripts", "TestimonialRunner", "driver.jl")
    @test isfile(path)
end

@testset "TestimonialRunner driver.jl uses env vars" begin
    path = joinpath(@__DIR__, "..", "scripts", "TestimonialRunner", "driver.jl")
    content = try
        read(path, String)
    catch
        @test false
        return
    end

    has_item = occursin("TESTIMONIAL_ITEM", content)
    has_file = occursin("TESTIMONIAL_FILE", content)
    has_runtests = occursin("ReTestItems.runtests", content)

    @test has_item
    @test has_file
    @test has_runtests

    # Check for exit code patterns
    has_exit0 = occursin("exit(0)", content)
    has_exit1 = occursin("exit(1)", content)

    @test has_exit0
    @test has_exit1
end