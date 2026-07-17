# Testimonial.jl — Tests for CoverageLayer subprocess command construction
#
# Verifies the subprocess command is built correctly with the right
# julia flags, project path, driver script, and environment variables.
#
# See REC-002 (subprocess invocation) and task 5.4 in
# openspec/changes/implement-coverage-layer/tasks.md

using Testimonial
using Test

@testset "build_driver_command: basic structure" begin
    cmd, env = Testimonial.build_driver_command("test/my_test.jl", "my item")

    @test cmd isa Vector{String}
    @test length(cmd) >= 4

    # First arg should be julia
    @test occursin("julia", cmd[1])

    # Should include --code-coverage (user on <1.12, tracefile.info on 1.12+)
    @test any(c -> occursin("--code-coverage", c), cmd)

    # Should include --project pointing to runner directory
    @test any(c -> occursin("--project", c) && occursin("TestimonialRunner", c), cmd)

    # Should reference driver.jl
    @test any(c -> occursin("driver.jl", c), cmd)
end

@testset "build_driver_command: environment variables" begin
    cmd, env = Testimonial.build_driver_command("test/my_test.jl", "my item")

    @test haskey(env, "TESTIMONIAL_FILE")
    @test haskey(env, "TESTIMONIAL_ITEM")

    @test env["TESTIMONIAL_FILE"] == "test/my_test.jl"
    @test env["TESTIMONIAL_ITEM"] == "my item"
end

@testset "build_driver_command: absolute paths" begin
    abs_path = "/home/user/project/test/foo.jl"
    cmd, env = Testimonial.build_driver_command(abs_path, "test_foo")

    @test env["TESTIMONIAL_FILE"] == abs_path
end

@testset "build_driver_command: special characters in item name" begin
    cmd, env = Testimonial.build_driver_command("test/bar.jl", "Black-Scholes call pricing")

    @test env["TESTIMONIAL_ITEM"] == "Black-Scholes call pricing"
end

@testset "build_driver_command: custom runner directory" begin
    cmd, env = Testimonial.build_driver_command(
        "test/foo.jl", "test_foo";
        runner_dir="/custom/runner"
    )

    @test any(c -> occursin("/custom/runner", c), cmd)
end