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

Returns a JSON response with a `nodes` array, each node having:
- `id`: unique node ID in `test_file:line` format
- `file`: absolute, normalized test file path
- `name`: the @testitem name

Errors on missing params, invalid directory, or non-existent path.
"""
function handle_discover(cmd)
    params = get(cmd, "params", nothing)
    if params === nothing
        return json_error("missing 'params' field")
    end

    dirs = get(params, "test_directories", nothing)
    if dirs === nothing || !isa(dirs, Vector)
        return json_error("missing or invalid 'params.test_directories'")
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
            "id" => "$(item.file):$(item.line)",
            "file" => item.file,
            "name" => item.name
        ))
    end

    return JSON.json(Dict(
        "ok" => true,
        "result" => Dict(
            "nodes" => nodes
        )
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
"""
function handle_ingest(cmd)
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

    # Build edges map: file_path -> {line_number -> [node_id, ...]}
    edges = Dict{String, Dict{String, Vector{String}}}()
    errors_list = []

    parent = Base.parentmodule(@__MODULE__)

    for item_id in selected
        # Parse node ID: file:line
        parts = split(item_id, ":", limit=2)
        if length(parts) != 2
            push!(errors_list, Dict(
                "id" => item_id,
                "error" => "invalid node ID format: $(item_id)"
            ))
            continue
        end
        file_path = parts[1]
        line_str = parts[2]

        line_num = try
            parse(Int, line_str)
        catch
            push!(errors_list, Dict(
                "id" => item_id,
                "error" => "invalid line number in node ID: $(item_id)"
            ))
            continue
        end

        # Resolve the node ID to a TestItemRef by scanning the file
        ref = _resolve_node_id(parent, file_path, line_num)
        if ref === nothing
            push!(errors_list, Dict(
                "id" => item_id,
                "error" => "no @testitem found at $(item_id)"
            ))
            continue
        end

        # Record coverage for this item
        coverage = try
            parent.record_item(ref)
        catch e
            push!(errors_list, Dict(
                "id" => item_id,
                "error" => "recording failed: $(sprint(showerror, e))"
            ))
            continue
        end

        if coverage === nothing
            push!(errors_list, Dict(
                "id" => item_id,
                "error" => "recording returned no coverage"
            ))
            continue
        end

        # Accumulate in session_coverage
        session_coverage[item_id] = coverage

        # Convert ItemCoverage to runtime edges
        # Each covered line creates an edge: file -> line -> [node_id]
        abs_file = isabspath(coverage.item.file) ? coverage.item.file : joinpath(pwd(), coverage.item.file)
        abs_file = realpath(abs_file)

        if !haskey(edges, abs_file)
            edges[abs_file] = Dict{String, Vector{String}}()
        end

        file_edges = edges[abs_file]

        for line in coverage.covered_lines
            line_key = string(line)
            if !haskey(file_edges, line_key)
                file_edges[line_key] = String[]
            end
            push!(file_edges[line_key], item_id)
        end

        for line in coverage.uncovered_lines
            line_key = string(line)
            if !haskey(file_edges, line_key)
                file_edges[line_key] = String[]
            end
            push!(file_edges[line_key], item_id)
        end
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
    tags = parent._parse_tags(content)
    pattern = r"@testitem\s+\"([^\"]+)\""

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

end # module Protocol