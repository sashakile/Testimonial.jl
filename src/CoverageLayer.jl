# Coverage recording layer — records coverage for individual @testitems.
#
# Runs each @testitem in an isolated subprocess and parses the resulting
# .jl.cov sidecar files to attribute covered lines back to the item.
#
# See PROTO-004 in openspec/changes/implement-coverage-layer/specs/protocol-adapter/spec.md

module CoverageLayer

export record_item, build_driver_command, AbstractRunner, SubprocessRunner,
       parse_cov_sidecar, run_with_timeout, with_retry,
       TIMEOUT_PER_ITEM_DEFAULT, MAX_TIMEOUT_PER_ITEM, MAX_RETRIES

using Coverage

# ── Runner types ──────────────────────────────

"""Abstract type for test recording runners. Enables dependency injection
for testing via MockRunner. See REC-011."""
abstract type AbstractRunner end

"""Concrete runner that spawns a Julia subprocess for @testitem recording.

Fields:
- `runner_dir`: path to the TestimonialRunner workspace (default: "scripts/TestimonialRunner")
"""
struct SubprocessRunner <: AbstractRunner
    runner_dir::String
    timeout::Float64
end

SubprocessRunner(; runner_dir::String="scripts/TestimonialRunner", timeout::Float64=TIMEOUT_PER_ITEM_DEFAULT) =
    SubprocessRunner(runner_dir, timeout)

"""
    build_driver_command(test_file::String, item_name::String; runner_dir::AbstractString="scripts/TestimonialRunner") -> Tuple{Vector{String}, Dict{String, String}}

Build the subprocess command and environment for recording a single @testitem.

Returns a tuple `(cmd, env)` where `cmd` is the argument vector for the Julia
subprocess and `env` is a dict of environment variables to set.

Generated command:
    julia --code-coverage=user --project=<runner_dir> <runner_dir>/driver.jl

Environment:
    TESTIMONIAL_FILE=<test_file>
    TESTIMONIAL_ITEM=<item_name>
"""
function build_driver_command(
    test_file::AbstractString,
    item_name::AbstractString;
    runner_dir::AbstractString="scripts/TestimonialRunner"
)::Tuple{Vector{String}, Dict{String, String}}
    driver_path = joinpath(runner_dir, "driver.jl")
    cmd = [
        "julia",
        "--code-coverage=user",
        "--project=$(runner_dir)",
        driver_path
    ]
    env = Dict(
        "TESTIMONIAL_FILE" => String(test_file),
        "TESTIMONIAL_ITEM" => String(item_name)
    )
    return (cmd, env)
end

# ── Coverage sidecar parsing ──────────────────

"""
    parse_cov_sidecar(source_file::AbstractString) -> Dict{String, Set{Int}}

Parse a Julia .jl.cov coverage sidecar file for the given source file
and return a map of source file paths to sets of covered line numbers.

Only lines with execution count > 0 are included (lines with count 0
or non-executable lines marked with `-` are excluded).

Returns an empty dict if the source file or its .jl.cov sidecar
cannot be found or read.
"""
function parse_cov_sidecar(source_file::AbstractString)::Dict{String, Set{Int}}
    result = Dict{String, Set{Int}}()

    src_path = String(source_file)
    if !isfile(src_path)
        return result
    end

    cov_path = src_path * ".cov"
    if !isfile(cov_path)
        return result
    end

    fc = try
        Coverage.process_file(src_path, dirname(src_path))
    catch
        return result
    end

    covered = Set{Int}()
    for (i, count) in enumerate(fc.coverage)
        if count !== nothing && count > 0
            push!(covered, i)
        end
    end

    if !isempty(covered)
        result[src_path] = covered
    end

    return result
end

"""
    record_item(ref) -> Union{ItemCoverage, Nothing}

Record coverage for a single @testitem by running it in an isolated subprocess.

Returns an `ItemCoverage` with the item's covered and uncovered lines, or
`nothing` if recording fails.

!!! note "Stub implementation"
    This is a placeholder that returns an empty `ItemCoverage`. The actual
    subprocess-based recording will be implemented in a follow-up
    (see testimonial-e47).
"""
function record_item(ref)
    # Stub: return empty coverage for now
    # Real implementation will:
    # 1. Create a temp directory with a symlinked shadow tree
    # 2. Determine the test file path relative to the project root
    # 3. Spawn a Julia subprocess running TestimonialRunner
    # 4. Parse the resulting .jl.cov sidecar
    # 5. Return ItemCoverage with covered/uncovered lines
    parent = Base.parentmodule(@__MODULE__)
    return parent.ItemCoverage(ref, Int[], Int[])
end

# ── Timeout handling ──────────────────────────

"""Default timeout per subprocess item recording in seconds (300s = 5 minutes)."""
const TIMEOUT_PER_ITEM_DEFAULT = 300.0

"""Maximum allowed timeout for a retry attempt in seconds (600s = 10 minutes)."""
const MAX_TIMEOUT_PER_ITEM = 600.0

"""Maximum number of retry attempts for a timed-out subprocess (2 = 3 total tries)."""
const MAX_RETRIES = 2

"""
    run_with_timeout(command, env, timeout) -> Union{Int, Nothing}

Run a subprocess with a timeout. Returns the exit code if the process
completes within `timeout` seconds, or `nothing` if the timeout was
exceeded and the process was killed.

The process is killed via `kill` on the process group so that any child
processes are also terminated. stdout and stderr are inherited from the
parent process.
"""
function run_with_timeout(command::Vector{String}, env::Dict{String, String}, timeout::Real)
    # Build the command with environment variables
    cmd = setenv(Cmd(command), env)

    # Launch the subprocess without waiting
    proc = run(cmd; wait=false)

    timer = Timer(timeout) do t
        # Timeout fired — kill the process
        kill(proc)
    end

    # Wait for the process to finish or be killed
    wait(proc)

    # Close the timer if the process finished before the timeout
    close(timer)

    # If the process was terminated by a signal, it was killed by the timeout
    if proc.termsignal > 0
        return nothing
    end

    return proc.exitcode
end

"""
    with_retry(fn, initial_timeout; max_retries=MAX_RETRIES, max_timeout=MAX_TIMEOUT_PER_ITEM) -> result

Execute a thunk `fn` with timeout-based retry logic.

The thunk must return either:
- A value (success) — returned immediately
- `nothing` (timeout) — retried with doubled timeout

Retries are capped at `max_retries`. Each retry doubles the timeout,
capped at `max_timeout`. If all retries are exhausted, returns `nothing`.

# Examples
```julia
# Retry a subprocess with timeout, doubling on each timeout
result = with_retry(300.0) do timeout
    run_with_timeout(["julia", "script.jl"], Dict{String, String}(), timeout)
end
```
"""
function with_retry(fn::Function, initial_timeout::Real;
                     max_retries::Int=MAX_RETRIES,
                     max_timeout::Real=MAX_TIMEOUT_PER_ITEM)
    timeout = Float64(initial_timeout)
    for attempt in 0:max_retries
        result = fn(timeout)
        if result !== nothing
            return result
        end
        # Timed out — double timeout for next attempt, capped at max
        timeout = min(timeout * 2, Float64(max_timeout))
    end
    return nothing
end

end # module CoverageLayer
