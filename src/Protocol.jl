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

"""
In-memory session coverage map, keyed by node ID (test_file:line).
Built incrementally across `ingest` calls in the same adapter session.
Queried by the `static-deps` handler (PROTO-005).
"""
const session_coverage = Dict{String, Any}()

"""
    run_adapter_protocol()

Main loop: reads JSON commands from stdin, dispatches to handlers,
writes JSON responses to stdout. Exits cleanly on EOF.
"""
function run_adapter_protocol()
    # Clear session state from any previous invocation in the same process
    empty!(session_coverage)

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
    # Use pwd() because testaruda spawns the adapter from the target project's root,
    # not from Pkg.test(). When running under Pkg.test() on Julia 1.12+ the caller
    # should pass explicit test_directories.
    _default_test_dir = joinpath(pwd(), "test")
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

    # Discover test items across all configured directories
    parent = Base.parentmodule(@__MODULE__)
    items = parent.discover_testitems(normalized_dirs)

    nodes = []
    for item in items
        push!(nodes, Dict(
            "node_id" => "$(item.file):$(item.line)",
            "suite_kind" => "ReTestItems.jl",
            "file" => item.file
        ))
    end

    return JSON.json(Dict(
        "ok" => true,
        "result" => nodes
    ))
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

    # Parse JSON lines
    lines = split(run_output, "\n", keepempty=false)
    test_results = []
    edge_dicts = []
    parent = Base.parentmodule(@__MODULE__)

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
        # ReTestItems outputs paths relative to pwd, but discover returns absolute paths.
        parts = split(test_id, ":", limit=2)
        if length(parts) == 2 && !isabspath(parts[1])
            abs_file = joinpath(pwd(), parts[1])
            test_id = "$(abs_file):$(parts[2])"
        end

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

        # Record coverage for this test item
        coverage = _record_item_for_ingest(parent, test_id)

        if coverage !== nothing
            # Build runtime edges from coverage
            _append_runtime_edges(coverage, test_id, edge_dicts)
        end
    end

    return JSON.json(Dict{String, Any}(
        "ok" => true,
        "result" => Dict{String, Any}(
            "runtime_edges" => edge_dicts,
            "per_test_results" => test_results,
            "external_inputs" => String[]
        )
    ))
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

    for m in eachmatch(pattern, content)
        name = m.captures[1]
        offset = m.offset
        item_line = count(==('\n'), content[1:offset]) + 1
        if item_line == line
            item_tags = get(tags, name, Symbol[])
            return parent.TestItemRef(file_str, line, name, item_tags, fhash)
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

    # Build ReTestItems.runtests invocation
    # Each selected item is in the format "test_file:item_name"
    # We emit a Julia expression that calls ReTestItems.runtests with
    # file and name filters for each selected item.
    file_filter_pairs = []
    for item in selected
        parts = split(item, ":", limit=2)
        if length(parts) == 2
            push!(file_filter_pairs, (parts[1], parts[2]))
        else
            # No colon — treat the whole string as a test file path
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

    # Build the Julia expression
    # ReTestItems.runtests(; filenames=[...], names=[...])
    test_files = collect(keys(file_groups))
    test_names = filter(x -> x !== nothing, vcat(values(file_groups)...))

    # Build the runner command
    # Use a single Julia invocation with ReTestItems.runtests
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

    # Collection path for JUnit-style results
    # ReTestItems outputs to stdout by default; we use a temp file
    collection_path = "test-results.xml"

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
        # No changed files → empty edges dict
        return JSON.json(Dict{String, Any}(
            "ok" => true,
            "result" => Dict{String, Any}("edges" => Dict{String, Any}())
        ))
    end

    for f in changed
        if !isa(f, String)
            return json_error("'params.changed_files' entries must be strings")
        end
    end

    # Build file→edges map, or mark as unresolved
    edges = _build_static_edges(changed)

    return JSON.json(Dict{String, Any}(
        "ok" => true,
        "result" => Dict{String, Any}("edges" => edges)
    ))
end

"""
    _build_static_edges(changed_files) -> Dict

Build dependency edges for the given changed files.

If session_coverage is empty, every changed file maps to "unresolved".
Otherwise, for each changed file, look up the recorded edges from
session_coverage (grouped by file).

File paths are normalized with realpath before comparison to ensure
absolute/relative path mismatches don't cause silent unresolved results.
"""
function _build_static_edges(changed_files)
    edges = Dict{String, Any}()

    if isempty(session_coverage)
        # No coverage recorded yet — all files are unresolved
        for f in changed_files
            edges[f] = "unresolved"
        end
        return edges
    end

    # Build a file→edges lookup from session_coverage
    # session_coverage keyed by node_id (file:line), value is ItemCoverage
    # Normalize file paths with realpath so the lookup is robust to
    # absolute/relative path mismatches with changed_files.
    file_edges = Dict{String, Dict{String, Vector{String}}}()

    for (node_id, coverage) in session_coverage
        # Add edges for the test file itself
        file = _normalize_path(coverage.item.file)
        if file !== nothing
            if !haskey(file_edges, file)
                file_edges[file] = Dict{String, Vector{String}}()
            end
            inner = file_edges[file]
            _add_line_edges(inner, coverage.covered_lines, node_id)
            _add_line_edges(inner, coverage.uncovered_lines, node_id)
        end

        # Add edges for each source file exercised by this test item
        for (src_path, (covered, uncovered)) in coverage.source_files
            norm_src = _normalize_path(src_path)
            if norm_src === nothing
                continue
            end
            if !haskey(file_edges, norm_src)
                file_edges[norm_src] = Dict{String, Vector{String}}()
            end
            src_inner = file_edges[norm_src]
            _add_line_edges(src_inner, covered, node_id)
            _add_line_edges(src_inner, uncovered, node_id)
        end
    end

    # For each changed file, normalize path and return edges or unresolved
    for f in changed_files
        norm_f = _normalize_path(f)
        if norm_f === nothing
            # Can't normalize the changed file path — mark as unresolved
            edges[f] = "unresolved"
        elseif haskey(file_edges, norm_f)
            edges[norm_f] = file_edges[norm_f]
        else
            edges[f] = "unresolved"
        end
    end

    return edges
end

end # module Protocol