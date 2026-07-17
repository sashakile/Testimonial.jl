# Test helpers for Testimonial.jl
#
# Shared test utilities used across multiple test files.

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