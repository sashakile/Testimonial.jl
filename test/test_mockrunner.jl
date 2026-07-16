# Testimonial.jl — Unit test for record_item with MockRunner
#
# Verifies that record_item constructs the correct subprocess command
# without actually spawning any processes. The MockRunner captures the
# command for inspection.
#
# See REC-011 in openspec/changes/implement-coverage-layer/specs/recording/spec.md

using Testimonial
using Test

# ── MockRunner ────────────────────────────────

"""A mock runner that captures the recording command without spawning."""
struct MockRunner <: Testimonial.AbstractRunner
    captured_cmd :: Vector{String}
    captured_env :: Dict{String, String}
end

MockRunner() = MockRunner(String[], Dict{String, String}())

"""Record coverage using MockRunner — captures command, doesn't spawn."""
function Testimonial.record_item(runner::MockRunner, ref::Testimonial.TestItemRef)
    cmd, env = Testimonial.build_driver_command(ref.file, ref.name)
    push!(runner.captured_cmd, cmd...)
    merge!(runner.captured_env, env)
    return Testimonial.ItemCoverage(ref, Int[], Int[])
end

# ── Tests ──────────────────────────────────────

@testset "MockRunner captures command" begin
    runner = MockRunner()
    ref = Testimonial.TestItemRef("test/foo.jl", 10, "test_foo")

    result = Testimonial.record_item(runner, ref)

    @test result isa Testimonial.ItemCoverage
    @test !isempty(runner.captured_cmd)
    @test occursin("julia", runner.captured_cmd[1])
    @test occursin("--code-coverage", join(runner.captured_cmd, " "))
end

@testset "MockRunner captures env vars" begin
    runner = MockRunner()
    ref = Testimonial.TestItemRef("test/bar.jl", 5, "test_bar")

    Testimonial.record_item(runner, ref)

    @test haskey(runner.captured_env, "TESTIMONIAL_FILE")
    @test haskey(runner.captured_env, "TESTIMONIAL_ITEM")
    @test runner.captured_env["TESTIMONIAL_FILE"] == "test/bar.jl"
    @test runner.captured_env["TESTIMONIAL_ITEM"] == "test_bar"
end

@testset "MockRunner does not spawn processes" begin
    runner = MockRunner()
    ref = Testimonial.TestItemRef("test/baz.jl", 15, "test_baz")

    # Just verify the method returns without error — no subprocess is spawned
    result = Testimonial.record_item(runner, ref)
    @test result isa Testimonial.ItemCoverage
end