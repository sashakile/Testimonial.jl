# Testimonial.jl — Tests for runner types (AbstractRunner, SubprocessRunner)
#
# Verifies the trait-based runner interface for decoupling subprocess
# command construction from execution. Enables testing via MockRunner.
#
# See REC-011 in openspec/changes/implement-coverage-layer/specs/recording/spec.md

using Testimonial
using Test

@testset "AbstractRunner is abstract type" begin
    @test isabstracttype(Testimonial.AbstractRunner)
end

@testset "SubprocessRunner is a subtype of AbstractRunner" begin
    @test SubprocessRunner <: Testimonial.AbstractRunner
end

@testset "SubprocessRunner has runner_dir and timeout fields" begin
    runner = SubprocessRunner()
    @test hasproperty(runner, :runner_dir)
    @test hasproperty(runner, :timeout)
    @test runner.runner_dir == "scripts/TestimonialRunner"
    @test runner.timeout == Testimonial.TIMEOUT_PER_ITEM_DEFAULT
end

@testset "SubprocessRunner custom runner_dir" begin
    runner = SubprocessRunner(runner_dir="/custom/path")
    @test runner.runner_dir == "/custom/path"
    @test runner.timeout == Testimonial.TIMEOUT_PER_ITEM_DEFAULT
end

@testset "SubprocessRunner custom timeout" begin
    runner = SubprocessRunner(timeout=60.0)
    @test runner.timeout == 60.0
end