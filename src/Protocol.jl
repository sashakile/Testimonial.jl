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

    # Dispatch
    if command == "handshake"
        return handle_handshake()
    elseif command == "fingerprint"
        return handle_fingerprint(cmd)
    elseif command == "run-args"
        return handle_run_args(cmd)
    else
        return json_error("unknown command: $(command)")
    end
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

Build a JSON error response per TIA-ADAPT-001 error format.
"""
function json_error(message)
    return JSON.json(Dict(
        "ok" => false,
        "error" => message
    ))
end

end # module Protocol