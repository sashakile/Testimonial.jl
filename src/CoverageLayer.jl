# Coverage recording layer — records coverage for individual @testitems.
#
# Runs each @testitem in an isolated subprocess and parses the resulting
# .jl.cov sidecar files to attribute covered lines back to the item.
#
# See PROTO-004 in openspec/changes/implement-coverage-layer/specs/protocol-adapter/spec.md

module CoverageLayer

export record_item, record_file, record_batch, build_driver_command, AbstractRunner, SubprocessRunner,
       parse_cov_sidecar, run_with_timeout, with_retry,
       TIMEOUT_PER_ITEM_DEFAULT, MAX_TIMEOUT_PER_ITEM, MAX_RETRIES,
       InferenceEdge, parse_inference_trace, inference_content_units

using Coverage
using Serialization

# ── Project root detection ────────────────────

"""
    _project_root() -> String

Find the project root directory by walking up from the module's source
file until we find `src/` at the top level. Used to locate source files
for symlinked shadow trees.
"""
function _project_root()::String
    # The module source is at src/CoverageLayer.jl, so project root is ../
    src_dir = joinpath(@__DIR__)
    return realpath(joinpath(src_dir, ".."))
end

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
    _base_driver_cmd(runner_dir) -> Vector{String}

Build the Julia argument vector shared by every recording invocation —
`julia <coverage-flag> --project=<runner_dir> <runner_dir>/driver.jl`.
`runner_dir` is resolved relative to the package source directory (not
the cwd) so the adapter can be spawned from any project.
"""
function _base_driver_cmd(runner_dir::AbstractString="scripts/TestimonialRunner")::Vector{String}
    pkg_root = realpath(joinpath(@__DIR__, ".."))
    abs_runner_dir = isabspath(runner_dir) ? runner_dir : joinpath(pkg_root, runner_dir)
    driver_path = joinpath(abs_runner_dir, "driver.jl")
    coverage_flag = _is_julia_12_or_later() ? "--code-coverage=tracefile.info" : "--code-coverage=user"
    return [
        "julia",
        coverage_flag,
        "--project=$(abs_runner_dir)",
        driver_path,
    ]
end

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
    cmd = _base_driver_cmd(runner_dir)
    env = Dict(
        "TESTIMONIAL_FILE" => String(test_file),
        "TESTIMONIAL_ITEM" => String(item_name)
    )
    return (cmd, env)
end

"""
    build_driver_command(test_file::AbstractString, item_names::AbstractVector; runner_dir=...) -> Tuple{Vector{String}, Dict{String, String}}

Batched variant: build the subprocess command for recording multiple
@testitems that share `test_file` in a single Julia invocation.

The item names are passed to the driver via the newline-separated
`TESTIMONIAL_ITEMS` environment variable. The single-item
`TESTIMONIAL_ITEM` var is intentionally omitted so the driver can
distinguish batch vs. single-item mode.

Coverage attribution: because Julia's LCOV tracefile accumulates over
the whole process lifetime and there is no in-process coverage-reset
API (see `openspec/changes/implement-coverage-layer/design.md`), the
tracefile produced by a batch reflects the UNION of coverage across
all items in the batch. Callers that attribute the resulting coverage
per-item therefore produce a safe over-approximation (each item in the
file maps to the file's full coverage) — coarser than per-item
isolation but never under-selecting. Use for bulk / initial recording
where the per-item startup cost dominates.
"""
function build_driver_command(
    test_file::AbstractString,
    item_names::AbstractVector;
    runner_dir::AbstractString="scripts/TestimonialRunner"
)::Tuple{Vector{String}, Dict{String, String}}
    cmd = _base_driver_cmd(runner_dir)
    names = String[String(n) for n in item_names]
    env = Dict{String, String}(
        "TESTIMONIAL_FILE" => String(test_file),
        "TESTIMONIAL_ITEMS" => join(names, "\n"),
    )
    return (cmd, env)
end

# ── Version detection ───────────────────────────

"""
    _is_julia_12_or_later() -> Bool

Check if the running Julia version is 1.12 or later, which uses LCOV
tracefiles instead of `.jl.cov` sidecar files for code coverage.
"""
_is_julia_12_or_later() = VERSION >= v"1.12.0"

"""
    _find_tracefile() -> Union{String, Nothing}

Search for a `tracefile.info` generated by Julia 1.12+ `--code-coverage=tracefile.info`.
Search order:
1. Current working directory (pwd) — where the subprocess generates it
2. Parent directories up to 3 levels from the source file
"""
function _find_tracefile()
    # First check pwd (most likely location — subprocess inherits cwd)
    tracefile = joinpath(pwd(), "tracefile.info")
    if isfile(tracefile)
        return tracefile
    end
    return nothing
end

# ── LCOV tracefile parsing ─────────────────────

"""
    _parse_lcov_tracefile(tracefile_path::AbstractString) -> Dict{String, Set{Int}}

Parse a Julia 1.12+ LCOV-format tracefile and return a map of source file
paths to sets of covered line numbers.

The LCOV format (as generated by Julia 1.12's `--code-coverage=tracefile.info`)
consists of records, each containing:
    SF:<source_file_path>
    DA:<line_number>,<execution_count>
    ...
    end_of_record

Only lines with execution count > 0 are included. Returns an empty dict
if the tracefile cannot be read or contains no valid records.
"""
function _parse_lcov_tracefile(tracefile_path::AbstractString)::Dict{String, Set{Int}}
    result = Dict{String, Set{Int}}()

    path = String(tracefile_path)
    if !isfile(path)
        return result
    end

    lines = try
        readlines(path)
    catch
        return result
    end

    current_src = nothing
    for line in lines
        # Source file declaration
        if startswith(line, "SF:")
            current_src = line[4:end]  # strip "SF:"
            continue
        end

        # Data line: DA:<line>,<count>
        if startswith(line, "DA:")
            if current_src === nothing
                continue
            end
            parts = split(line[4:end], ",")  # strip "DA:"
            if length(parts) != 2
                continue
            end
            lineno = try
                parse(Int, parts[1])
            catch
                continue
            end
            count = try
                parse(Int, parts[2])
            catch
                continue
            end
            if count > 0
                covered = get!(result, current_src, Set{Int}())
                push!(covered, lineno)
            end
            continue
        end

        # End of record
        if line == "end_of_record"
            current_src = nothing
            continue
        end
    end

    return result
end

# ── Coverage sidecar parsing ──────────────────

"""
    parse_cov_sidecar(source_file::AbstractString) -> Dict{String, Set{Int}}

Parse a Julia .jl.cov coverage sidecar file for the given source file
and return a map of source file paths to sets of covered line numbers.

Only lines with execution count > 0 are included (lines with count 0
or non-executable lines marked with `-` are excluded).

On Julia 1.12+, also attempts to parse an LCOV tracefile (`tracefile.info`)
as a fallback if no `.jl.cov` sidecar is found.

Returns an empty dict if no coverage data can be found or read.
"""
function parse_cov_sidecar(source_file::AbstractString)::Dict{String, Set{Int}}
    result = Dict{String, Set{Int}}()

    src_path = String(source_file)
    if !isfile(src_path)
        return result
    end

    # Julia < 1.12: look for .jl.cov sidecar
    cov_path = src_path * ".cov"
    if isfile(cov_path)
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

    # Julia 1.12+: try LCOV tracefile as fallback
    if _is_julia_12_or_later()
        # Look for tracefile.info in the source file's directory
        # and parent directories (up to 3 levels)
        search_dir = dirname(src_path)
        for _ in 1:3
            tracefile = joinpath(search_dir, "tracefile.info")
            if isfile(tracefile)
                lcov_result = _parse_lcov_tracefile(tracefile)
                if haskey(lcov_result, src_path) && !isempty(lcov_result[src_path])
                    return Dict(src_path => lcov_result[src_path])
                end
            end
            parent = dirname(search_dir)
            if parent == search_dir
                break
            end
            search_dir = parent
        end
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
    # Default to SubprocessRunner with default settings
    return record_item(SubprocessRunner(), ref)
end

"""
    record_item(runner::SubprocessRunner, ref) -> Union{ItemCoverage, Nothing}

Record coverage for a single @testitem by spawning an isolated Julia
subprocess. Creates a temp directory with a symlinked shadow tree of
src/ and test/ to isolate `.jl.cov` output.

Returns an `ItemCoverage` with covered and uncovered lines, or `nothing`
if recording fails (timeout, infrastructure error, etc.).
"""
function record_item(runner::SubprocessRunner, ref)
    parent = Base.parentmodule(@__MODULE__)

    # Validate the test file exists
    test_file = String(ref.file)
    if !isfile(test_file)
        return nothing
    end

    # Build the subprocess command
    cmd, env = build_driver_command(test_file, ref.name; runner_dir=runner.runner_dir)

    # Run the subprocess with timeout and retry
    exitcode = with_retry(runner.timeout) do timeout
        run_with_timeout(cmd, env, timeout)
    end

    if exitcode === nothing
        # All retries exhausted — timeout
        return nothing
    end

    # Parse coverage from the subprocess output
    test_covered, test_uncovered, source_files = _collect_coverage(test_file, parent)

    return parent.ItemCoverage(ref, test_covered, test_uncovered, source_files)
end

# ── Batched recording ─────────────────────────

"""
    record_batch(runner::AbstractRunner, refs::Vector) -> Vector{Union{ItemCoverage, Nothing}}

Record coverage for a batch of @testitems. Default implementation loops
`record_item` per ref — subtypes that can amortise subprocess startup
cost (e.g. `SubprocessRunner`) override this to collapse the batch into
a single subprocess invocation.

All refs in a batch SHOULD share the same `test_file`; callers (notably
`record_all` with `batch_by_file=true`) are responsible for grouping
by file before invoking.
"""
function record_batch(runner::AbstractRunner, refs::Vector)
    parent = Base.parentmodule(@__MODULE__)
    return [parent.record_item(runner, ref) for ref in refs]
end

"""
    record_batch(runner::SubprocessRunner, refs) -> Vector{Union{ItemCoverage, Nothing}}

Record a batch of @testitems sharing one test file in a single Julia
subprocess. The driver runs every item in the batch; the resulting LCOV
tracefile holds the UNION of coverage across the batch, which is
attributed to each ref (safe over-approximation — see
`build_driver_command` batch variant).

Returns one `ItemCoverage` per ref (all sharing the file's aggregate
coverage), or `nothing` per ref if the subprocess fails.
"""
function record_batch(runner::SubprocessRunner, refs::Vector)
    parent = Base.parentmodule(@__MODULE__)
    isempty(refs) && return Union{parent.ItemCoverage, Nothing}[]

    test_file = String(refs[1].file)
    if !isfile(test_file)
        return Union{parent.ItemCoverage, Nothing}[nothing for _ in refs]
    end

    names = String[r.name for r in refs]
    cmd, env = build_driver_command(test_file, names; runner_dir=runner.runner_dir)

    exitcode = with_retry(runner.timeout) do timeout
        run_with_timeout(cmd, env, timeout)
    end

    nothings = Union{parent.ItemCoverage, Nothing}[nothing for _ in refs]

    if exitcode === nothing
        return nothings
    end

    test_covered, test_uncovered, source_files = _collect_coverage(test_file, parent)
    return [parent.ItemCoverage(ref, test_covered, test_uncovered, source_files) for ref in refs]
end

# ── File-level recording ────────────────────────

"""
    build_driver_command(test_file::AbstractString; runner_dir=...) -> Tuple{Vector{String}, Dict{String, String}}

File-level variant: build the subprocess command for running ALL tests
in a file (not filtered by @testitem name). Sets `TESTIMONIAL_RUN_ALL=true`
so the driver runs via `ReTestItems.runtests(test_file)` without filtering.

Used for recording coverage of @testset-based repos where individual test
blocks cannot be isolated in separate subprocesses.
"""
function build_driver_command(
    test_file::AbstractString;
    runner_dir::AbstractString="scripts/TestimonialRunner"
)::Tuple{Vector{String}, Dict{String, String}}
    cmd = _base_driver_cmd(runner_dir)
    env = Dict{String, String}(
        "TESTIMONIAL_FILE" => String(test_file),
        "TESTIMONIAL_RUN_ALL" => "true",
    )
    return (cmd, env)
end

"""
    record_file(runner::AbstractRunner, test_file::AbstractString) -> Union{ItemCoverage, Nothing}

Record coverage for all tests in a file as a single subprocess invocation.
Returns a single `ItemCoverage` attributed to the file as a whole (line=0).

This is the file-level equivalent of `record_item`. Used for @testset-based
repos where individual test blocks cannot be isolated in subprocesses.

Returns `nothing` if the file doesn't exist or the subprocess fails.
"""
function record_file(runner::AbstractRunner, test_file::AbstractString)
    parent = Base.parentmodule(@__MODULE__)

    if !isfile(test_file)
        return nothing
    end

    cmd, env = build_driver_command(test_file; runner_dir=runner.runner_dir)

    exitcode = with_retry(runner.timeout) do timeout
        run_with_timeout(cmd, env, timeout)
    end

    if exitcode === nothing
        return nothing
    end

    test_covered, test_uncovered, source_files = _collect_coverage(test_file, parent)

    # Create a file-level ref (line=0, name=filename)
    ref = parent.TestItemRef(test_file, 0, basename(test_file))
    return parent.ItemCoverage(ref, test_covered, test_uncovered, source_files)
end

"""
    _collect_coverage(test_file, parent) -> Tuple{Vector{Int}, Vector{Int}, Dict{String, Tuple{Vector{Int}, Vector{Int}}}}

Find and parse coverage for the given test file after a subprocess run.

Returns a tuple of:
1. `covered_lines` — lines in the test file that were covered
2. `uncovered_lines` — lines in the test file that were not covered
3. `source_files` — a dict mapping source file paths to `(covered, uncovered)`
   line tuples for ALL source files that were exercised by the test

On Julia 1.12+, the LCOV tracefile contains entries for source files that were
compiled and executed (e.g., `src/foo.jl`), not the test file itself (which is
loaded via `eval` by ReTestItems). The `source_files` dict captures this
per-source-file coverage data for edge building.

On Julia < 1.12, `.jl.cov` sidecar files are generated next to each source file.
The test file's coverage is parsed directly, and additional source files are
scanned from the project's src/ directory.

After parsing, all coverage artifacts are cleaned up to prevent interference
with subsequent recordings.
"""
function _collect_coverage(test_file::String, parent::Module)
    covered_lines = Int[]
    uncovered_lines = Int[]
    source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}()

    if _is_julia_12_or_later()
        # ── LCOV tracefile path (Julia 1.12+) ──
        tracefile = _find_tracefile()
        lcov_result = _parse_lcov_tracefile(tracefile)

        # Build per-source-file coverage dict
        for (src, covered_set) in lcov_result
            sorted_covered = sort!(collect(covered_set))
            # Read the source file to compute total lines for uncovered set
            content = try
                read(src, String)
            catch
                continue
            end
            total_lines = count(==('\n'), content)
            sorted_uncovered = sort!(collect(setdiff(Set(1:total_lines), covered_set)))
            source_files[src] = (sorted_covered, sorted_uncovered)

            # If this is the test file, also set the top-level return values
            if src == test_file
                covered_lines = sorted_covered
                uncovered_lines = sorted_uncovered
            end
        end

        # Clean up tracefile
        try
            rm(tracefile; force=true)
        catch
        end
    else
        # ── .jl.cov sidecar path (Julia < 1.12) ──
        pkg_root = _project_root()
        cov_files = String[]

        # Scan the test file's directory
        test_dir = dirname(test_file)
        for f in readdir(test_dir)
            if endswith(f, ".cov")
                push!(cov_files, joinpath(test_dir, f))
            end
        end

        # Also scan the project's src/ directory
        src_dir = joinpath(pkg_root, "src")
        if isdir(src_dir)
            for f in readdir(src_dir)
                if endswith(f, ".cov")
                    push!(cov_files, joinpath(src_dir, f))
                end
            end
        end

        # Parse coverage for the test file
        covered = parse_cov_sidecar(test_file)

        if haskey(covered, test_file)
            content = try
                read(test_file, String)
            catch
                ""
            end
            total_lines = count(==('\n'), content)
            covered_set = covered[test_file]
            covered_lines = sort!(collect(covered_set))
            uncovered_lines = sort!(collect(setdiff(Set(1:total_lines), covered_set)))
        end

        # Also scan parsed .jl.cov files for source-level coverage
        for cov_file in cov_files
            src_path = cov_file[1:end-4]  # strip .cov suffix
            if isfile(src_path)
                src_covered = parse_cov_sidecar(src_path)
                if haskey(src_covered, src_path)
                    content = try
                        read(src_path, String)
                    catch
                        continue
                    end
                    total_lines = count(==('\n'), content)
                    src_cov_set = src_covered[src_path]
                    src_cov_lines = sort!(collect(src_cov_set))
                    src_uncovered = sort!(collect(setdiff(Set(1:total_lines), src_cov_set)))
                    source_files[src_path] = (src_cov_lines, src_uncovered)
                end
            end
        end

        # Clean up all discovered .jl.cov files
        for cov_file in cov_files
            try
                rm(cov_file; force=true)
            catch
            end
        end
        # Clean up the inference trace sidecar (testimonial-1v4f).
        try
            rm(joinpath(pwd(), "inference_trace.jls"); force=true)
        catch
        end
    end

    return (covered_lines, uncovered_lines, source_files)
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
function run_with_timeout(command::Vector{String}, env::Dict{String, String}, timeout::Real)::Union{Int, Nothing}
    # Build the command with environment variables (addenv preserves existing PATH)
    cmd = addenv(Cmd(command), env)

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

# ── Inference trace parsing (testimonial-be7o) ─
# The subprocess driver (driver.jl, testimonial-1v4f) serializes the
# caller→callee edges captured by SnoopCompile to an `inference_trace.jls`
# sidecar. Each edge is a 6-tuple:
#   (caller_name, caller_file, caller_line, callee_name, callee_file, callee_line)
# Plain primitives only — the sidecar deserializes cleanly without
# SnoopCompile on the reading side.

"""A single inference caller→callee edge.

`(caller_name, caller_file, caller_line, callee_name, callee_file, callee_line)`.
"""
const InferenceEdge = Tuple{String, String, Int, String, String, Int}

"""
    parse_inference_trace(path::AbstractString) -> Vector{InferenceEdge}

Deserialize an `inference_trace.jls` sidecar produced by the subprocess
driver into a vector of inference edges.

Returns an empty `Vector{InferenceEdge}` if the file is missing, unreadable,
or contains no edges — inference capture is always optional (the driver
falls back to coverage-only when SnoopCompile is unavailable), so the
parser must never throw on absent data.

See openspec/project.md — inference-layer capability (Phase 2).
Ref: testimonial-1v4f (capture), testimonial-be7o (parse + populate).
"""
function parse_inference_trace(path::AbstractString)::Vector{InferenceEdge}
    p = String(path)
    isfile(p) || return InferenceEdge[]
    try
        data = open(Serialization.deserialize, p, "r")
        data isa AbstractVector || return InferenceEdge[]
        return InferenceEdge[e for e in data if e isa InferenceEdge]
    catch
        return InferenceEdge[]
    end
end

"""
    inference_content_units(edges::AbstractVector{InferenceEdge}) -> Vector{Tuple{String, Int}}

Project the *caller* source locations from a vector of inference edges —
the content units that get attributed to the owning test item. Deduped.

Per the inference-layer spec, each inferred call records the caller source
location as a content unit and maps it to the test item that triggered
inference; the callee is preserved in the stored edge for richer queries.
"""
function inference_content_units(edges::AbstractVector)::Vector{Tuple{String, Int}}
    seen = Set{Tuple{String, Int}}()
    for e in edges
        e isa InferenceEdge || continue
        push!(seen, (e[2], e[3]))  # (caller_file, caller_line)
    end
    return collect(seen)
end

end # module CoverageLayer
