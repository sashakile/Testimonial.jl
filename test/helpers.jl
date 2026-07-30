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
    batches :: Vector{Vector{String}}
    lock :: ReentrantLock
end

MockRunner() = MockRunner(String[], Dict{String, String}(), Vector{Vector{String}}(), ReentrantLock())

"""Record coverage using MockRunner — captures command, doesn't spawn."""
function Testimonial.record_item(runner::MockRunner, ref::Testimonial.TestItemRef)
    cmd, env = Testimonial.build_driver_command(ref.file, ref.name)
    lock(runner.lock) do
        push!(runner.captured_cmd, cmd...)
        merge!(runner.captured_env, env)
    end
    return Testimonial.ItemCoverage(ref, Int[], Int[], Dict())
end

"""Record a batch of items in one (mock) subprocess invocation.

Captures the batched item-name list so tests can assert that
`record_all(...; batch_by_file=true)` collapses N items into one
subprocess per file rather than one per item.
"""
function Testimonial.record_batch(runner::MockRunner, refs::Vector{Testimonial.TestItemRef})
    names = String[r.name for r in refs]
    file = refs[1].file
    cmd, env = Testimonial.build_driver_command(file, names)
    lock(runner.lock) do
        push!(runner.captured_cmd, cmd...)
        merge!(runner.captured_env, env)
        push!(runner.batches, names)
    end
    return [Testimonial.ItemCoverage(r, Int[], Int[], Dict()) for r in refs]
end

"""Record file-level coverage using MockRunner — captures command, doesn't spawn."""
function Testimonial.record_file(runner::MockRunner, test_file::String)
    cmd, env = Testimonial.build_driver_command(test_file)
    lock(runner.lock) do
        push!(runner.captured_cmd, cmd...)
        merge!(runner.captured_env, env)
    end
    ref = Testimonial.TestItemRef(test_file, 0, basename(test_file))
    return Testimonial.ItemCoverage(ref, Int[], Int[], Dict())
end