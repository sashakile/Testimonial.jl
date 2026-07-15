# Protocol adapter — JSON stdin/stdout protocol for testaruda integration.
#
# Layer 2 entry point: reads one JSON command per line from stdin and writes
# one JSON response per line to stdout. Used by testaruda as a subprocess
# adapter for Julia projects.
#
# See PROTO-001 through PROTO-007 in openspec/changes/implement-coverage-layer/specs/protocol-adapter/spec.md

module Protocol

using JSON

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