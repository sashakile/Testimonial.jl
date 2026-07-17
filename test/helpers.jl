# Test helpers for Testimonial.jl
#
# Shared test utilities used across multiple test files.

# ── MockRunner ────────────────────────────────

"""A mock runner that captures the recording command without spawning.

Thread-safe: uses a lock for captured_cmd and captured_env mutations
since `record_all` calls `record_item` from multiple threads.
"""
struct MockRunner <: Testimonial.AbstractRunner
    captured_cmd :: Vector{String}
    captured_env :: Dict{String, String}
    lock :: ReentrantLock
end

MockRunner() = MockRunner(String[], Dict{String, String}(), ReentrantLock())

"""Record coverage using MockRunner — captures command, doesn't spawn."""
function Testimonial.record_item(runner::MockRunner, ref::Testimonial.TestItemRef)
    cmd, env = Testimonial.build_driver_command(ref.file, ref.name)
    lock(runner.lock) do
        push!(runner.captured_cmd, cmd...)
        merge!(runner.captured_env, env)
    end
    return Testimonial.ItemCoverage(ref, Int[], Int[])
end