# Protocol adapter — JSON stdin/stdout protocol for testaruda integration.
#
# Layer 2 entry point: reads one JSON command per line from stdin and writes
# one JSON response per line to stdout. Used by testaruda as a subprocess
# adapter for Julia projects.
#
# See PROTO-001 through PROTO-007 in openspec/changes/implement-coverage-layer/specs/protocol-adapter/spec.md

module Protocol

using JSON
using SHA

export run_adapter_protocol

# ── Protocol response schema (testimonial-nl2b.2) ────────────────
# The standard dependency-edge representation across protocol responses.
# Every `static-deps` edge and every `ingest` (run_output) inference/runtime
# edge is a JSON object with EXACTLY these four fields — no more, no less.
# Pinning the field set here keeps the contract self-documenting in code
# and lets contract tests guard against silent drift.
#
# Field semantics:
#   from   — String; the depending unit (a test node id `file:line`, or a
#            caller location `file:line` for inference edges)
#   to     — String; the depended-on unit (a source file path for static
#            edges, or a `file:line` location for inference/runtime edges)
#   weight — Int; edge weight (currently a fixed sentinel, 1_000_000)
#   origin — String; the layer that produced the edge: "static",
#            "inference", or "runtime"
const DEPEDGE_FIELDS = ("from", "to", "weight", "origin")

"""
In-memory session coverage map, keyed by node ID (test_file:line).
Built incrementally across `ingest` calls in the same adapter session.
Queried by the `static-deps` handler (PROTO-005).
"""
const session_coverage = Dict{String, Any}()

"""
In-memory session static edges, keyed by source file path, valued by
sets of node IDs (test_file:line). Populated from CoverageIndex.static_edges
when a CoverageIndex is available on disk.

Used by the `static-deps` handler (PROTO-005) to provide concrete
dependency edges based on static analysis (abstract dispatch, declared
entrypoints) when no in-session coverage has been recorded.
"""
const session_static_edges = Dict{String, Set{String}}()

"""
    run_adapter_protocol()

Main loop: reads JSON commands from stdin, dispatches to handlers,
writes JSON responses to stdout. Exits cleanly on EOF.
"""
function run_adapter_protocol()
    # Clear session state from any previous invocation in the same process
    empty!(session_coverage)
    empty!(session_static_edges)

    while !eof(stdin)
        line = readline(stdin)
        if isnothing(line)
            break
        end
        stripped = strip(line)
        if isempty(stripped)
            continue
        end

        response = handle(stripped)
        println(response)
        flush(stdout)
    end
end

"""
    handle(line) -> String

Parse a JSON command string, dispatch to the appropriate handler,
and return the JSON response string.
"""
function handle(line)
    # Convert SubString to String if needed
    line_str = String(line)

    # Parse JSON
    cmd = try
        JSON.parse(line_str)
    catch e
        return json_error("malformed JSON: $(sprint(showerror, e))")
    end

    # Extract command name
    command = get(cmd, "command", "")
    if isempty(command)
        return json_error("missing 'command' field")
    end

    # Dispatch via lookup table
    handlers = Dict{String, Function}(
        "handshake" => () -> handle_handshake(),
        "discover" => () -> handle_discover(cmd),
        "ingest" => () -> handle_ingest(cmd),
        "static-deps" => () -> handle_static_deps(cmd),
        "fingerprint" => () -> handle_fingerprint(cmd),
        "run-args" => () -> handle_run_args(cmd),
    )
    handler = get(handlers, command, nothing)
    if isnothing(handler)
        return json_error("unknown command: $(command)")
    end
    return handler()
end

"""
    handle_handshake() -> String

Return the static handshake capability declaration per PROTO-002.
"""
function handle_handshake()
    response = Dict(
        "ok" => true,
        "result" => Dict(
            "name" => "testimonial-adapter",
            "version" => "0.1.0",
            "protocol" => 1,
            "languages" => ["julia"],
            "granularity" => "file",
            "capabilities" => Dict(
                "symbol_model_complete" => false,
                "fingerprinting" => true,
                "runtime_edges" => true
            )
        )
    )
    return JSON.json(response)
end

"""
    handle_fingerprint(cmd::Dict) -> String

Compute SHA-256 hashes for the requested files per PROTO-006.
Responds with an array of `{file, fingerprint}` objects.
Uses SHA-256 (not BLAKE3) to avoid non-stdlib dependencies.
"""
function handle_fingerprint(cmd)
    params = get(cmd, "params", nothing)
    if params === nothing
        return json_error("missing 'params' field")
    end

    files = get(params, "files", nothing)
    if files === nothing || !isa(files, Vector) || isempty(files)
        return json_error("missing or empty 'params.files'")
    end

    fingerprints = []
    for file in files
        if !isa(file, String)
            return json_error("'params.files' entries must be strings")
        end
        if !isfile(file)
            return json_error("file not found: $(file)")
        end
        content = try
            read(file)
        catch e
            return json_error("cannot read $(file): $(sprint(showerror, e))")
        end
        hash = bytes2hex(sha256(content))
        push!(fingerprints, Dict(
            "file" => file,
            "fingerprint" => hash,
            "symbol" => nothing
        ))
    end

    return JSON.json(Dict(
        "ok" => true,
        "result" => Dict(
            "fingerprints" => fingerprints
        )
    ))
end

"""
    handle_discover(cmd::Dict) -> String

Respond to the `discover` command by scanning configured test directories
for @testitem blocks per PROTO-003.

Returns a JSON response with a flat array of test items, each having:
- `node_id`: unique node ID in `test_file:line` format
- `suite_kind`: always "ReTestItems.jl"
- `file`: absolute, normalized test file path

Errors on missing params, invalid directory, or non-existent path.
"""
function handle_discover(cmd)
    params = get(cmd, "params", nothing)

    # Default to the project's test directory when no params provided.
    # First try pwd()/test/ which works in external adapter mode (testaruda sets
    # cwd to the target project root) and in local dev (cwd = repo root).
    # If pwd()/test/ doesn't exist, fall back to @__DIR__/../test/ which is
    # correct under Pkg.test on Julia 1.12+ (cwd = test/ subdirectory).
    _default_test_dir = joinpath(pwd(), "test")
    if !isdir(_default_test_dir)
        _default_test_dir = joinpath(dirname(@__DIR__), "test")
    end
    if params === nothing
        dirs = [_default_test_dir]
    else
        dirs = get(params, "test_directories", nothing)
        if dirs === nothing || !isa(dirs, Vector)
            dirs = [_default_test_dir]
        end
    end

    # Validate and normalize directories to absolute paths
    normalized_dirs = String[]
    for d in dirs
        if !isa(d, String)
            return json_error("'params.test_directories' entries must be strings")
        end
        if !isdir(d)
            return json_error("not a directory: $(d)")
        end
        push!(normalized_dirs, realpath(d))
    end

    # Discover all test blocks (@testitem, @testset, file-level fallback)
    # across all configured directories
    parent = Base.parentmodule(@__MODULE__)
    items = parent.discover_all_test_blocks(normalized_dirs)

    nodes = []
    for item in items
        # Determine suite_kind based on item properties
        suite_kind = if item.line == 0
            # File-level fallback (no test blocks found)
            "Base.Test"
        elseif _is_testitem_at_line(item.file, item.line)
            "ReTestItems.jl"
        else
            "Base.Test"
        end

        push!(nodes, Dict(
            "node_id" => "$(item.file):$(item.line)",
            "suite_kind" => suite_kind,
            "file" => item.file
        ))
    end

    return JSON.json(Dict(
        "ok" => true,
        "result" => nodes
    ))
end

"""
    _is_testitem_at_line(file::AbstractString, line::Int) -> Bool

Check whether the given line in a file contains a @testitem block.
Scans the file for @testitem patterns and checks if any match the line.
"""
function _is_testitem_at_line(file::AbstractString, line::Int)::Bool
    if !isfile(file)
        return false
    end
    if line == 0
        return false  # File-level fallback, not a real line
    end
    content = try
        read(file, String)
    catch
        return false
    end
    parent = Base.parentmodule(@__MODULE__)
    pattern = parent._TESTITEM_PATTERN
    for m in eachmatch(pattern, content)
        offset = m.offset
        item_line = count(==('\n'), content[1:offset]) + 1
        if item_line == line
            return true
        end
    end
    return false
end

"""
    handle_ingest(cmd::Dict) -> String

Respond to the `ingest` command by recording coverage for the specified
test items per PROTO-004.

Parses node IDs (test_file:line), calls CoverageLayer.record_item for each,
converts ItemCoverage to runtime edges (file→line→test), and accumulates
results in session_coverage.

Returns edges inline in the response, keyed by absolute file path.
On partial failure, the response includes a `result.errors` array
with per-item error entries (invalid IDs, missing files, recording failures).
"""
function handle_ingest(cmd)
    params = get(cmd, "params", nothing)
    if params === nothing
        return json_error("missing 'params' field")
    end

    # Check for run_output format (TIA-ADAPT-008)
    run_output = get(params, "run_output", nothing)
    if run_output !== nothing
        return _handle_ingest_run_output(cmd, params)
    end

    selected = get(params, "selected", nothing)
    if selected === nothing || !isa(selected, Vector) || isempty(selected)
        return json_error("missing or empty 'params.selected' or 'params.run_output'")
    end

    for item in selected
        if !isa(item, String)
            return json_error("'params.selected' entries must be strings")
        end
    end

    # Build edges map: file_path -> {line_number -> [node_id, ...]}
    edges = Dict{String, Dict{String, Vector{String}}}()
    errors_list = []

    parent = Base.parentmodule(@__MODULE__)

    for item_id in selected
        _ingest_one_item(parent, item_id, edges, errors_list)
    end

    result = Dict{String, Any}("edges" => edges)
    if !isempty(errors_list)
        result["errors"] = errors_list
    end

    return JSON.json(Dict{String, Any}(
        "ok" => true,
        "result" => result
    ))
end

"""
    _handle_ingest_run_output(cmd, params) -> String

Handle the `ingest` command when `params.run_output` is provided (TIA-ADAPT-008).

Parses the run_output string (JSON lines), extracts @testitem results,
records coverage for each, and returns the standard response format:
- `runtime_edges`: Vec<DepEdge> with {from, to, weight, origin}
- `per_test_results`: Vec<TestRunResult> with {test_id, outcome, duration_ms, error_text}
- `external_inputs`: Vec<String> (empty, reserved for future use)
"""
function _handle_ingest_run_output(cmd, params)
    run_output = params["run_output"]

    if !isa(run_output, String)
        return json_error("'params.run_output' must be a string")
    end

    # Parse JSON lines — collect entries, group by file for batched coverage
    lines = split(run_output, "\n", keepempty=false)
    test_results = []
    edge_dicts = []
    parent = Base.parentmodule(@__MODULE__)

    # First pass: parse all entries and group by file
    # file_group[file_path] = [(test_id, outcome, duration_ms, error_text), ...]
    file_groups = Dict{String, Vector{Tuple{String, String, Union{Int, Nothing}, Union{String, Nothing}}}}()

    for line in lines
        stripped = strip(line)
        if isempty(stripped)
            continue
        end

        entry = try
            JSON.parse(stripped)
        catch e
            return json_error("malformed JSON in 'params.run_output': $(sprint(showerror, e))")
        end

        if !isa(entry, AbstractDict)
            return json_error("'params.run_output' entries must be JSON objects")
        end

        test_id = get(entry, "test_id", nothing)
        if test_id === nothing || !isa(test_id, String)
            return json_error("'params.run_output' entries must have a 'test_id' string field")
        end

        # Resolve relative paths in test_id to absolute.
        parts = split(test_id, ":", limit=2)
        if length(parts) == 2 && !isabspath(parts[1])
            abs_file = joinpath(pwd(), parts[1])
            test_id = "$(abs_file):$(parts[2])"
        end

        file_path = parts[1]
        outcome = get(entry, "outcome", "passed")
        duration_ms = get(entry, "duration_ms", nothing)
        error_text = get(entry, "error_text", nothing)

        # Build per-test result entry
        test_entry = Dict{String, Any}(
            "test_id" => test_id,
            "outcome" => outcome
        )
        if duration_ms !== nothing
            test_entry["duration_ms"] = duration_ms
        end
        if error_text !== nothing
            test_entry["error_text"] = error_text
        end
        push!(test_results, test_entry)

        if !haskey(file_groups, file_path)
            file_groups[file_path] = []
        end
        push!(file_groups[file_path], (test_id, outcome, duration_ms, error_text))
    end

    # Second pass: batch-record coverage per file (shares one Julia subprocess)
    runner = parent.SubprocessRunner()

    for (file_path, entries) in file_groups
        # Resolve all refs for this file
        refs = parent.TestItemRef[]
        for (test_id, _, _, _) in entries
            test_parts = split(test_id, ":", limit=2)
            if length(test_parts) != 2
                continue
            end
            line_num = try
                parse(Int, test_parts[2])
            catch
                continue
            end
            ref = _resolve_node_id(parent, test_parts[1], line_num)
            if ref !== nothing
                push!(refs, ref)
            end
        end

        if isempty(refs)
            continue
        end

        # Record all refs in this file with a single subprocess
        coverages = parent.record_batch(runner, refs)

        # Build edges from each coverage result
        for (i, coverage) in enumerate(coverages)
            if coverage !== nothing && i <= length(entries)
                test_id = entries[i][1]
                _append_runtime_edges(coverage, test_id, edge_dicts)
                session_coverage[test_id] = coverage
            end
        end
    end

    # Read inference trace sidecar if present (testimonial-3t08)
    inference_edges = _build_inference_edges()

    return JSON.json(Dict{String, Any}(
        "ok" => true,
        "result" => Dict{String, Any}(
            "runtime_edges" => edge_dicts,
            "inference_edges" => inference_edges,
            "per_test_results" => test_results,
            "external_inputs" => String[]
        )
    ))
end

"""
    _build_inference_edges() -> Vector{Dict}

Read the inference trace sidecar (`inference_trace.jls`) and convert each
`InferenceEdge` (caller_name, caller_file, caller_line, callee_name,
callee_file, callee_line) to a DepEdge dict with `origin: "inference"`.

Returns an empty array if no trace file exists or parsing fails.
Cleans up the trace file after reading.
"""
function _build_inference_edges()
    parent = Base.parentmodule(@__MODULE__)
    trace_path = joinpath(pwd(), "inference_trace.jls")

    isfile(trace_path) || return Vector{Dict{String, Any}}()

    edges = Vector{Dict{String, Any}}()
    try
        raw_edges = parent.parse_inference_trace(trace_path)
        for e in raw_edges
            # e is InferenceEdge: (caller_name, caller_file, caller_line, callee_name, callee_file, callee_line)
            push!(edges, Dict{String, Any}(
                "from" => "$(e[2]):$(e[3])",       # caller_file:caller_line
                "to" => "$(e[5]):$(e[6])",          # callee_file:callee_line
                "weight" => 1_000_000,
                "origin" => "inference"
            ))
        end
    catch
        # If parsing fails, return empty (graceful degradation)
    end

    # Clean up the trace file
    try
        rm(trace_path; force=true)
    catch
    end

    return edges
end

"""
    _record_item_for_ingest(parent, test_id) -> Union{ItemCoverage, Nothing}

Record coverage for a single test item identified by node_id (file:line).
Returns the ItemCoverage or nothing on failure. Also accumulates in
session_coverage for downstream static-deps queries.
"""
function _record_item_for_ingest(parent, test_id)
    # Parse node ID: file:line
    parts = split(test_id, ":", limit=2)
    if length(parts) != 2
        return nothing
    end

    line_num = try
        parse(Int, parts[2])
    catch
        return nothing
    end

    # Resolve the node ID to a TestItemRef by scanning the file
    ref = _resolve_node_id(parent, parts[1], line_num)
    if ref === nothing
        return nothing
    end

    # Record coverage for this item
    coverage = try
        parent.record_item(ref)
    catch
        return nothing
    end

    if coverage === nothing
        return nothing
    end

    # Accumulate in session_coverage
    session_coverage[test_id] = coverage

    return coverage
end

"""
    _append_runtime_edges(coverage, test_id, edge_dicts)

Build DepEdge entries from coverage data and append to edge_dicts.
Each covered or uncovered line becomes a DepEdge:
{from: test_id, to: "source_file:line", weight: 1000000, origin: "runtime"}
"""
function _append_runtime_edges(coverage, test_id, edge_dicts)
    # Emit per-source-file edges from source_files map (Julia 1.12+ LCOV).
    # This contains the actual source files that the test exercised (e.g., src/foo.jl).
    # The tracefile only tracks source files, not test files loaded via eval.
    for (src_file, (covered, uncovered)) in coverage.source_files
        norm_file = _normalize_path(src_file)
        src = norm_file === nothing ? src_file : norm_file
        for line in covered
            push!(edge_dicts, Dict{String, Any}(
                "from" => test_id,
                "to" => "$(src):$(line)",
                "weight" => 1000000,
                "origin" => "runtime"
            ))
        end
        for line in uncovered
            push!(edge_dicts, Dict{String, Any}(
                "from" => test_id,
                "to" => "$(src):$(line)",
                "weight" => 1000000,
                "origin" => "runtime"
            ))
        end
    end

    # Also emit edges for the test file's own covered/uncovered lines (Julia < 1.12)
    # Only do this when source_files is empty to avoid duplication.
    if isempty(coverage.source_files)
        file = _normalize_path(coverage.item.file)
        if file === nothing
            file = coverage.item.file
        end
        for line in coverage.covered_lines
            push!(edge_dicts, Dict{String, Any}(
                "from" => test_id,
                "to" => "$(file):$(line)",
                "weight" => 1000000,
                "origin" => "runtime"
            ))
        end
        for line in coverage.uncovered_lines
            push!(edge_dicts, Dict{String, Any}(
                "from" => test_id,
                "to" => "$(file):$(line)",
                "weight" => 1000000,
                "origin" => "runtime"
            ))
        end
    end
end

"""
    _ingest_one_item(parent, item_id, edges, errors_list)

Process a single node ID through the ingest pipeline: parse, resolve,
record, accumulate, and build edges. Modifies `edges` and `errors_list`
in place. On failure, pushes an error entry and returns without modifying edges.
"""
function _ingest_one_item(parent, item_id, edges, errors_list)
    # Parse node ID: file:line
    parts = split(item_id, ":", limit=2)
    if length(parts) != 2
        push!(errors_list, Dict(
            "node_id" => item_id,
            "error" => "invalid node ID format: $(item_id)"
        ))
        return
    end
    file_path = parts[1]
    line_str = parts[2]

    line_num = try
        parse(Int, line_str)
    catch
        push!(errors_list, Dict(
            "node_id" => item_id,
            "error" => "invalid line number in node ID: $(item_id)"
        ))
        return
    end

    # Resolve the node ID to a TestItemRef by scanning the file
    ref = _resolve_node_id(parent, file_path, line_num)
    if ref === nothing
        push!(errors_list, Dict(
            "node_id" => item_id,
            "error" => "no @testitem found at $(item_id)"
        ))
        return
    end

    # Record coverage for this item
    coverage = try
        parent.record_item(ref)
    catch e
        push!(errors_list, Dict(
            "node_id" => item_id,
            "error" => "recording failed: $(sprint(showerror, e))"
        ))
        return
    end

    if coverage === nothing
        push!(errors_list, Dict(
            "node_id" => item_id,
            "error" => "recording returned no coverage"
        ))
        return
    end

    # Accumulate in session_coverage
    session_coverage[item_id] = coverage

    # Convert ItemCoverage to runtime edges
    _build_edges_for_item(coverage, item_id, edges)
end

"""
    _build_edges_for_item(coverage, item_id, edges)

Convert an ItemCoverage to runtime edges: for each covered and uncovered
line in the coverage, map file→line→[item_id]. Modifies `edges` in place.
"""
function _build_edges_for_item(coverage, item_id, edges)
    # Add edges for the test file itself (test file's line coverage)
    abs_file = _normalize_path(coverage.item.file)
    if abs_file !== nothing
        if !haskey(edges, abs_file)
            edges[abs_file] = Dict{String, Vector{String}}()
        end
        file_edges = edges[abs_file]
        _add_line_edges(file_edges, coverage.covered_lines, item_id)
        _add_line_edges(file_edges, coverage.uncovered_lines, item_id)
    end

    # Add edges for each source file that was exercised by this test item.
    # On Julia 1.12+, the LCOV tracefile contains entries for source files
    # (e.g., src/foo.jl) that were compiled and executed, not the test file
    # itself (which is loaded via eval by ReTestItems).
    for (src_path, (covered, uncovered)) in coverage.source_files
        norm_src = _normalize_path(src_path)
        if norm_src === nothing
            continue
        end
        if !haskey(edges, norm_src)
            edges[norm_src] = Dict{String, Vector{String}}()
        end
        src_edges = edges[norm_src]
        _add_line_edges(src_edges, covered, item_id)
        _add_line_edges(src_edges, uncovered, item_id)
    end
end

"""
    _normalize_path(path) -> Union{String, Nothing}

Normalize a file path to absolute form via realpath.
Returns nothing if normalization fails (file doesn't exist, etc.).
"""
function _normalize_path(path)
    try
        abs = isabspath(path) ? path : joinpath(pwd(), path)
        return realpath(abs)
    catch
        return nothing
    end
end

"""Add a batch of line→[node_id] entries to an edge dict."""
function _add_line_edges(file_edges, lines, item_id)
    for line in lines
        line_key = string(line)
        if !haskey(file_edges, line_key)
            file_edges[line_key] = String[]
        end
        push!(file_edges[line_key], item_id)
    end
end

"""
    _resolve_node_id(parent::Module, file::String, line::Int) -> Union{TestItemRef, Nothing}

Resolve a (file, line) pair to a TestItemRef by scanning the file for
@testitem blocks. Returns nothing if no match is found.
"""
function _resolve_node_id(parent::Module, file::AbstractString, line::Int)
    file_str = String(file)
    if !isfile(file_str)
        return nothing
    end
    content = try
        read(file_str, String)
    catch
        return nothing
    end

    fhash = bytes2hex(sha256(content))[1:12]
    # _parse_tags is a private helper in the parent module — used here to
    # avoid duplicating tag-parsing logic. The pattern is shared via
    # parent._TESTITEM_PATTERN to keep the regex in one place.
    tags = parent._parse_tags(content)
    pattern = parent._TESTITEM_PATTERN

    # First, try to match @testitem blocks
    for m in eachmatch(pattern, content)
        name = m.captures[1]
        offset = m.offset
        item_line = count(==('\n'), content[1:offset]) + 1
        if item_line == line
            item_tags = get(tags, name, Symbol[])
            return parent.TestItemRef(file_str, line, name, item_tags, fhash)
        end
    end

    # If line == 0, it's a file-level fallback — return a placeholder
    if line == 0
        return parent.TestItemRef(file_str, 0, basename(file_str))
    end

    # Try to match @testset blocks
    testset_pattern = parent._TESTSET_PATTERN
    testset_unnamed = parent._TESTSET_UNNAMED_PATTERN
    for m in eachmatch(testset_pattern, content)
        name = m.captures[1]
        offset = m.offset
        item_line = count(==('\n'), content[1:offset]) + 1
        if item_line == line
            return parent.TestItemRef(file_str, line, name, Symbol[], fhash)
        end
    end
    for m in eachmatch(testset_unnamed, content)
        offset = m.offset
        item_line = count(==('\n'), content[1:offset]) + 1
        if item_line == line
            return parent.TestItemRef(file_str, line, "", Symbol[], fhash)
        end
    end

    return nothing
end

"""
    handle_run_args(cmd::Dict) -> String

Emit `ReTestItems.runtests` invocation arguments for the selected
test items per PROTO-007. Does NOT execute the tests.
"""
function handle_run_args(cmd)
    params = get(cmd, "params", nothing)
    if params === nothing
        return json_error("missing 'params' field")
    end

    selected = get(params, "selected", nothing)
    if selected === nothing || !isa(selected, Vector) || isempty(selected)
        return json_error("missing or empty 'params.selected'")
    end

    for item in selected
        if !isa(item, String)
            return json_error("'params.selected' entries must be strings")
        end
    end

    # Determine whether we have @testitem (ReTestItems) or @testset (Base.Test) items.
    # Each selected item is in the format "test_file:line_number" (from discover)
    # or "test_file:name" (backwards compat for direct usage).
    # We scan the file at the given line to determine the type.
    has_testset = false
    has_testitem = false
    file_filter_pairs = []
    for item in selected
        parts = split(item, ":", limit=2)
        if length(parts) == 2
            line_num = try
                parse(Int, parts[2])
            catch
                -1  # Not a valid line number — treat as test name (backwards compat)
            end
            if line_num >= 0 && _is_testitem_at_line(parts[1], line_num)
                has_testitem = true
            elseif line_num >= 0
                # Line number but not a @testitem — could be @testset or file-level fallback
                has_testset = true
            else
                # Not a line number (e.g., "test_file:test_name") — assume @testitem name
                has_testitem = true
            end
            push!(file_filter_pairs, (parts[1], parts[2]))
        else
            # No colon — treat the whole string as a test file path
            has_testset = true  # assume Base.Test
            push!(file_filter_pairs, (item, nothing))
        end
    end

    # Group by file to avoid duplicate invocations
    file_groups = Dict{String, Vector{Union{String, Nothing}}}()
    for (file, name) in file_filter_pairs
        if !haskey(file_groups, file)
            file_groups[file] = []
        end
        if name !== nothing
            push!(file_groups[file], name)
        end
    end

    test_files = collect(keys(file_groups))

    if has_testset
        # Use include() for Base.Test files
        # Build a single Julia expression that includes all unique test files
        include_exprs = ["include(\"$(escape_string(f))\")" for f in test_files]
        combined = join(include_exprs, "; ")

        runner_args = [
            "julia",
            "--project=.",
            "-e",
            "using Test; $(combined)"
        ]
        collection_path = "test-results.xml"
    else
        # All @testitem — use ReTestItems.runtests
        test_names = filter(x -> x !== nothing, vcat(values(file_groups)...))

        filter_expr = "ReTestItems.runtests("
        if !isempty(test_files)
            filter_expr *= "files=" * JSON.json(test_files)
        end
        if !isempty(test_names)
            if !isempty(test_files)
                filter_expr *= ", "
            end
            filter_expr *= "names=" * JSON.json(test_names)
        end
        filter_expr *= ")"

        runner_args = [
            "julia",
            "--project=.",
            "-e",
            "using ReTestItems; $(filter_expr)"
        ]
        collection_path = "test-results.xml"
    end

    return JSON.json(Dict(
        "ok" => true,
        "result" => Dict(
            "runner_args" => runner_args,
            "collection_path" => collection_path
        )
    ))
end

"""
    json_error(message::String) -> String

Build a JSON error response per PROTO-001 error format:
`{ "error": { "message": "..." } }`.
"""
function json_error(message)
    return JSON.json(Dict(
        "ok" => false,
        "error" => Dict("message" => message)
    ))
end

"""
    handle_static_deps(cmd::Dict) -> String

Respond to the `static-deps` command by returning dependency edges for
changed files per PROTO-005.

If no coverage has been recorded in this session (session_coverage is empty),
all changed files map to "unresolved", triggering testaruda's full-run fallback.

If coverage has been recorded, looks up each changed file in the
session_coverage map and returns the recorded edges.
"""
function handle_static_deps(cmd)
    params = get(cmd, "params", nothing)
    if params === nothing
        return json_error("missing 'params' field")
    end

    changed = get(params, "changed_files", nothing)
    if changed === nothing || !isa(changed, Vector)
        return json_error("missing or invalid 'params.changed_files'")
    end

    if isempty(changed)
        return JSON.json(Dict{String, Any}(
            "ok" => true,
            "result" => Dict{String, Any}("edges" => Vector{Any}())
        ))
    end

    for f in changed
        if !isa(f, String)
            return json_error("'params.changed_files' entries must be strings")
        end
    end

    edges = _build_static_edges(changed)

    return JSON.json(Dict{String, Any}(
        "ok" => true,
        "result" => Dict{String, Any}("edges" => edges)
    ))
end

"""
    _build_static_edges(changed_files) -> Vector{Dict}

Build dependency edges for the given changed files in the standard
DepEdge format: `[{from, to, weight, origin}]` where:
- `from` is the test node_id (file:line)
- `to` is the source file path
- `weight` is 1_000_000 (multiplicative identity)
- `origin` is "static"

When session_coverage is empty (no ingest done), checks `session_static_edges`
for static analysis data. If static edges are available, emits concrete
edges from the static analysis. If neither is available, returns an empty
array (the core's fallback logic marks files as "unresolved").
"""
function _build_static_edges(changed_files)
    edges = Vector{Dict{String, Any}}()

    if isempty(session_coverage)
        # No coverage recorded yet — try static edges from the CoverageIndex
        _ensure_session_static_edges_loaded()
        if !isempty(session_static_edges)
            return _emit_static_edges(changed_files)
        end
        # No coverage and no static data — emit no edges.
        # The core marks changed files without content units as "unresolved"
        # and falls back to full-run selection for low-confidence items.
        return edges
    end



    # Build a set of normalized file paths from changed_files for O(1) lookup
    changed_set = Set{String}()
    for f in changed_files
        norm_f = _normalize_path(f)
        if norm_f !== nothing
            push!(changed_set, norm_f)
        end
    end

    # Iterate over session_coverage and emit edges for any coverage
    # source_file that exists in the changed set
    for (node_id, coverage) in session_coverage
        # Emit edges for each source file exercised by this test item
        for (src_path, (covered, _)) in coverage.source_files
            norm_src = _normalize_path(src_path)
            if norm_src === nothing
                continue
            end
            if norm_src in changed_set
                push!(edges, Dict{String, Any}(
                    "from" => node_id,
                    "to" => norm_src,
                    "weight" => 1_000_000,
                    "origin" => "static"
                ))
            end
        end

        # Also emit edges for the test file's own coverage
        # (when the test file itself is in the changed set)
        file = _normalize_path(coverage.item.file)
        if file !== nothing && file in changed_set
            push!(edges, Dict{String, Any}(
                "from" => node_id,
                "to" => file,
                "weight" => 1_000_000,
                "origin" => "static"
            ))
        end
    end

    return edges
end

"""
    _ensure_session_static_edges_loaded()

Load static edges from the CoverageIndex on disk into `session_static_edges`
if not already loaded.

Reads `.testimonial/index.jls` and extracts `static_edges`
(`Dict{String, Set{TestItemRef}}`), converting each TestItemRef to a node_id
format (`file:line`).

Does nothing if the index file doesn't exist, can't be deserialized, or
has no static_edges. Does nothing if already loaded (idempotent).
"""
function _ensure_session_static_edges_loaded()
    isempty(session_static_edges) || return nothing

    parent = Base.parentmodule(@__MODULE__)
    index_path = ".testimonial/index.jls"

    index = try
        parent.load_index(index_path)
    catch
        nothing
    end

    index === nothing && return nothing
    isempty(index.static_edges) && return nothing

    # Convert TestItemRefs to node_id format (file:line)
    for (src_file, test_items) in index.static_edges
        isempty(test_items) && continue
        node_ids = Set{String}()
        for ref in test_items
            push!(node_ids, "$(ref.file):$(ref.line)")
        end
        session_static_edges[src_file] = node_ids
    end

    return nothing
end

"""
    _emit_static_edges(changed_files) -> Vector{Dict}

Emit DepEdge entries for changed files that have static analysis edges
in `session_static_edges`.

Called by `_build_static_edges` when `session_coverage` is empty but
static edges are available.
"""
function _emit_static_edges(changed_files)
    edges = Vector{Dict{String, Any}}()

    # Normalize changed file paths (resolve if possible, fall back to absolute)
    changed_set = Set{String}()
    for f in changed_files
        norm_f = _normalize_path(f)
        if norm_f !== nothing
            push!(changed_set, norm_f)
        else
            # File doesn't exist on disk — use absolute path as fallback
            abs_f = isabspath(f) ? f : joinpath(pwd(), f)
            push!(changed_set, abs_f)
        end
    end

    for (src_file, node_ids) in session_static_edges
        # Normalize the static edge source file path
        norm_src = _normalize_path(src_file)
        if norm_src === nothing
            # File doesn't exist — use absolute path as fallback
            norm_src = isabspath(src_file) ? src_file : joinpath(pwd(), src_file)
        end

        norm_src in changed_set || continue

        for node_id in node_ids
            push!(edges, Dict{String, Any}(
                "from" => node_id,
                "to" => norm_src,
                "weight" => 1_000_000,
                "origin" => "static"
            ))
        end
    end

    return edges
end

end # module Protocol