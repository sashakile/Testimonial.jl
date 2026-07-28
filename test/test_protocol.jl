# Protocol adapter tests — handshake, fingerprint, run-args handlers
#
# Tests for PROTO-002 (handshake), PROTO-006 (fingerprint), PROTO-007 (run-args).

using Testimonial
using Testimonial.Protocol
using Test
using JSON
using SHA

# ── Handshake handler (PROTO-002) ──────────────

@testset "Handshake response" begin
    resp = Protocol.handle("""{"command":"handshake"}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    @test haskey(parsed, "result")

    result = parsed["result"]
    @test haskey(result, "name")
    @test haskey(result, "version")
    @test haskey(result, "protocol")
    @test haskey(result, "languages")
    @test haskey(result, "granularity")
    @test haskey(result, "capabilities")

    @test result["protocol"] == 1
    @test result["languages"] == ["julia"]
    @test result["granularity"] == "file"

    caps = result["capabilities"]
    @test haskey(caps, "symbol_model_complete")
    @test haskey(caps, "fingerprinting")
    @test haskey(caps, "runtime_edges")

    @test caps["symbol_model_complete"] == false
    @test caps["fingerprinting"] == true
    @test caps["runtime_edges"] == true
end

@testset "Handshake response has name and version" begin
    resp = Protocol.handle("""{"command":"handshake"}""")
    parsed = JSON.parse(resp)

    result = parsed["result"]
    @test result["name"] == "testimonial-adapter"
    @test result["version"] == "0.1.0"
end

# ── Error handling (PROTO-001) ─────────────────

@testset "Malformed JSON" begin
    resp = Protocol.handle("not json")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == false
    @test haskey(parsed, "error")
    @test haskey(parsed["error"], "message")
    @test occursin("malformed JSON", parsed["error"]["message"])
end

@testset "Unknown command" begin
    resp = Protocol.handle("""{"command":"bogus"}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == false
    @test haskey(parsed, "error")
    @test haskey(parsed["error"], "message")
    @test occursin("unknown command", parsed["error"]["message"])
end

@testset "Missing command field" begin
    resp = Protocol.handle("""{"foo":"bar"}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == false
    @test haskey(parsed, "error")
    @test haskey(parsed["error"], "message")
    @test occursin("missing 'command' field", parsed["error"]["message"])
end

@testset "Empty input" begin
    resp = Protocol.handle("")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == false
    @test haskey(parsed, "error")
    @test haskey(parsed["error"], "message")
end

@testset "Fingerprint single file" begin
    mktemp() do path, io
        write(io, "hello world")
        flush(io)
        cmd = """{"command":"fingerprint","params":{"files":["$(path)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        results = parsed["result"]["fingerprints"]
        @test length(results) == 1
        @test results[1]["file"] == path
        @test occursin(r"^[0-9a-f]{64}$", results[1]["fingerprint"])
        @test results[1]["symbol"] === nothing
    end
end

@testset "Fingerprint multiple files" begin
    mktemp() do path1, io1
        write(io1, "content a")
        flush(io1)
        mktemp() do path2, io2
            write(io2, "content b")
            flush(io2)
            cmd = """{"command":"fingerprint","params":{"files":["$(path1)","$(path2)"]}}"""
            resp = Protocol.handle(cmd)
            parsed = JSON.parse(resp)

            @test parsed["ok"] == true
            results = parsed["result"]["fingerprints"]
            @test length(results) == 2
            @test results[1]["file"] == path1
            @test results[2]["file"] == path2
            @test results[1]["fingerprint"] != results[2]["fingerprint"]
        end
    end
end

@testset "Fingerprint deterministic output" begin
    mktemp() do path, io
        write(io, "deterministic input")
        flush(io)
        cmd = """{"command":"fingerprint","params":{"files":["$(path)"]}}"""
        resp1 = Protocol.handle(cmd)
        resp2 = Protocol.handle(cmd)

        @test resp1 == resp2
    end
end

@testset "Fingerprint SHA-256 length (64 hex chars)" begin
    mktemp() do path, io
        write(io, "any content")
        flush(io)
        cmd = """{"command":"fingerprint","params":{"files":["$(path)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        fp = parsed["result"]["fingerprints"][1]["fingerprint"]
        @test length(fp) == 64
    end
end

@testset "Fingerprint matches direct SHA-256 computation" begin
    content = "verify me"
    mktemp() do path, io
        write(io, content)
        flush(io)
        cmd = """{"command":"fingerprint","params":{"files":["$(path)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        fp = parsed["result"]["fingerprints"][1]["fingerprint"]
        expected = bytes2hex(sha256(content))
        @test fp == expected
    end
end

@testset "Fingerprint empty file" begin
    mktemp() do path, io
        close(io)
        cmd = """{"command":"fingerprint","params":{"files":["$(path)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        fp = parsed["result"]["fingerprints"][1]["fingerprint"]
        @test length(fp) == 64
        # SHA-256 of empty string
        expected = bytes2hex(sha256(""))
        @test fp == expected
    end
end

@testset "Fingerprint missing params.files" begin
    resp = Protocol.handle("""{"command":"fingerprint","params":{}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("missing or empty", parsed["error"]["message"])
end

@testset "Fingerprint missing params" begin
    resp = Protocol.handle("""{"command":"fingerprint"}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("missing 'params'", parsed["error"]["message"])
end

@testset "Fingerprint nonexistent file" begin
    cmd = """{"command":"fingerprint","params":{"files":["/nonexistent/path.jl"]}}"""
    resp = Protocol.handle(cmd)
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("file not found", parsed["error"]["message"])
end

# ── Run-args handler (PROTO-007) ───────────────

@testset "Run-args single test item" begin
    resp = Protocol.handle("""{"command":"run-args","params":{"selected":["test/test_foo.jl:test_bar"]}}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    result = parsed["result"]
    @test haskey(result, "runner_args")
    @test haskey(result, "collection_path")
    @test result["runner_args"][1] == "julia"
    @test result["runner_args"][2] == "--project=."
    @test result["runner_args"][3] == "-e"
    # Should contain ReTestItems.runtests reference
    @test occursin("ReTestItems", result["runner_args"][4])
    @test occursin("test_foo", result["runner_args"][4])
    @test occursin("test_bar", result["runner_args"][4])
end

@testset "Run-args multiple test items" begin
    resp = Protocol.handle("""{"command":"run-args","params":{"selected":["test_a.jl:item_1","test_b.jl:item_2"]}}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    result = parsed["result"]
    @test occursin("test_a.jl", result["runner_args"][4])
    @test occursin("test_b.jl", result["runner_args"][4])
    @test occursin("item_1", result["runner_args"][4])
    @test occursin("item_2", result["runner_args"][4])
end

@testset "Run-args multiple items same file" begin
    resp = Protocol.handle("""{"command":"run-args","params":{"selected":["test_a.jl:item_1","test_a.jl:item_2"]}}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    result = parsed["result"]
    args = result["runner_args"]
    # Should reference both items
    @test occursin("item_1", args[4])
    @test occursin("item_2", args[4])
end

@testset "Run-args has collection path" begin
    resp = Protocol.handle("""{"command":"run-args","params":{"selected":["test_a.jl:item_1"]}}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    result = parsed["result"]
    @test result["collection_path"] == "test-results.xml"
end

@testset "Run-args missing selected" begin
    resp = Protocol.handle("""{"command":"run-args","params":{}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("missing or empty", parsed["error"]["message"])
end

@testset "Run-args missing params" begin
    resp = Protocol.handle("""{"command":"run-args"}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("missing 'params'", parsed["error"]["message"])
end

@testset "Run-args empty selected" begin
    resp = Protocol.handle("""{"command":"run-args","params":{"selected":[]}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("missing or empty", parsed["error"]["message"])
end
# ── Discover handler (PROTO-003) ───────────────

@testset "Discover returns nodes with id, file, name" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_foo.jl")
        write(test_file, """
        @testitem "test_one" begin
            @test 1 == 1
        end
        @testitem "test_two" tags=[:slow] begin
            @test 2 == 2
        end
        """)
        cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test length(nodes) == 2

        # Both nodes should have the same file (absolute)
        @test nodes[1]["file"] == realpath(test_file)
        @test nodes[2]["file"] == realpath(test_file)

        @test nodes[1]["suite_kind"] == "ReTestItems.jl"
        @test nodes[2]["suite_kind"] == "ReTestItems.jl"

        # Node IDs should be file:line format
        @test occursin("test_foo.jl:", nodes[1]["node_id"])
        @test occursin("test_foo.jl:", nodes[2]["node_id"])
        @test nodes[1]["node_id"] != nodes[2]["node_id"]
    end
end

@testset "Discover returns absolute normalized paths" begin
    mktempdir() do dir
        subdir = joinpath(dir, "sub")
        mkpath(subdir)
        test_file = joinpath(subdir, "bar.jl")
        write(test_file, """@testitem "my_test" begin end""")
        cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test length(nodes) == 1
        @test nodes[1]["file"] == realpath(test_file)
        @test isabspath(nodes[1]["file"])
    end
end

@testset "Discover empty directories returns empty nodes" begin
    mktempdir() do dir
        # Empty directory with no .jl files
        cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test isempty(nodes)
    end
end

@testset "Discover empty test_directories list" begin
    resp = Protocol.handle("""{"command":"discover","params":{"test_directories":[]}}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    nodes = parsed["result"]
    @test isempty(nodes)
end

@testset "Discover missing params defaults to test/" begin
    resp = Protocol.handle("""{"command":"discover"}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == true
    nodes = parsed["result"]
    @test length(nodes) > 0
    @test nodes[1]["suite_kind"] == "ReTestItems.jl"
end

@testset "Discover missing test_directories defaults to test/" begin
    resp = Protocol.handle("""{"command":"discover","params":{}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == true
    nodes = parsed["result"]
    @test length(nodes) > 0
end

@testset "Discover non-existent directory" begin
    resp = Protocol.handle("""{"command":"discover","params":{"test_directories":["/nonexistent/path"]}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("not a directory", parsed["error"]["message"])
end

# ── Protocol loop integration tests (stdin/stdout) ───────────────

# ── Protocol loop integration tests (stdin/stdout) ───────────────

"""
Run a sequence of JSON commands through the protocol loop and return
the parsed response lines. Uses redirect_stdin / redirect_stdout to
simulate pipe communication.
"""
function run_protocol_commands(commands::Vector{String})
    # Save originals before redirecting
    old_stdin = stdin
    old_stdout = stdout
    in_read, in_write = redirect_stdin()
    out_read, out_write = redirect_stdout()

    try
        for cmd in commands
            write(in_write, cmd * "\n")
        end
        close(in_write)

        Protocol.run_adapter_protocol()

        # Close write end so readavailable can read remaining data
        close(out_write)

        # Read all response data
        output = String(readavailable(out_read))
        responses = split(strip(output), "\n")
        return responses
    finally
        # Restore global stdin/stdout
        redirect_stdin(old_stdin)
        redirect_stdout(old_stdout)
        close(out_read)
        close(out_write)
    end
end

@testset "Protocol loop: handshake via stdin/stdout" begin
    responses = run_protocol_commands(["""{"command":"handshake"}"""])
    @test length(responses) == 1

    parsed = JSON.parse(responses[1])
    @test parsed["ok"] == true
    @test parsed["result"]["name"] == "testimonial-adapter"
    @test parsed["result"]["protocol"] == 1
    @test parsed["result"]["languages"] == ["julia"]
    @test parsed["result"]["granularity"] == "file"
    @test parsed["result"]["capabilities"]["fingerprinting"] == true
    @test parsed["result"]["capabilities"]["runtime_edges"] == true
end

@testset "Protocol loop: discover via stdin/stdout" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_foo.jl")
        write(test_file, """@testitem "my_test" begin end""")
        cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        responses = run_protocol_commands([cmd])
        @test length(responses) == 1

        parsed = JSON.parse(responses[1])
        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test length(nodes) == 1
@test nodes[1]["suite_kind"] == "ReTestItems.jl"
        @test nodes[1]["file"] == realpath(test_file)
        @test occursin(":", nodes[1]["node_id"])
    end
end

@testset "Protocol loop: multiple commands in sequence" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_a.jl")
        write(test_file, """@testitem "test_a" begin end""")
        cmds = [
            """{"command":"handshake"}""",
            """{"command":"discover","params":{"test_directories":["$(dir)"]}}""",
            """{"command":"handshake"}""",
        ]
        responses = run_protocol_commands(cmds)
        @test length(responses) == 3

        # Verify all three responses are valid JSON
        for (i, resp) in enumerate(responses)
            parsed = JSON.parse(resp)
            @test parsed["ok"] == true
        end

        # First and third are handshake, middle is discover
        hs1 = JSON.parse(responses[1])
        disc = JSON.parse(responses[2])
        hs2 = JSON.parse(responses[3])

        @test hs1["result"]["name"] == "testimonial-adapter"
        @test length(disc["result"]) == 1
        @test disc["result"][1]["suite_kind"] == "ReTestItems.jl"
        @test hs2["result"]["name"] == "testimonial-adapter"
    end
end

@testset "Protocol loop: malformed JSON via stdin" begin
    responses = run_protocol_commands(["not json"])
    @test length(responses) == 1

    parsed = JSON.parse(responses[1])
    @test parsed["ok"] == false
    @test haskey(parsed, "error")
    @test occursin("malformed JSON", parsed["error"]["message"])
end

@testset "Protocol loop: unknown command via stdin" begin
    responses = run_protocol_commands(["""{"command":"bogus"}"""])
    @test length(responses) == 1

    parsed = JSON.parse(responses[1])
    @test parsed["ok"] == false
    @test haskey(parsed, "error")
    @test occursin("unknown command", parsed["error"]["message"])
end

@testset "Protocol loop: error response format" begin
    # Verify error responses follow { "error": { "message": "..." } } format
    responses = run_protocol_commands([
        "not json",
        """{"command":"bogus"}""",
    ])
    @test length(responses) == 2

    for resp in responses
        parsed = JSON.parse(resp)
        @test parsed["ok"] == false
        @test haskey(parsed, "error")
        @test haskey(parsed["error"], "message")
        @test isa(parsed["error"]["message"], String)
        @test !isempty(parsed["error"]["message"])
        # No extra fields in error
        @test length(keys(parsed["error"])) == 1
    end
end

@testset "Protocol loop: empty lines are skipped" begin
    # Empty lines should be skipped (no output), only valid commands produce output
    responses = run_protocol_commands([
        "",
        """{"command":"handshake"}""",
        "   ",
        """{"command":"handshake"}""",
    ])
    # 4 lines input, but 2 are empty/whitespace → only 2 responses
    @test length(responses) == 2

    for resp in responses
        parsed = JSON.parse(resp)
        @test parsed["ok"] == true
        @test parsed["result"]["name"] == "testimonial-adapter"
    end
end

# ── Ingest handler (PROTO-004) ────────────────

@testset "Ingest returns edges with ok=true" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_foo.jl")
        write(test_file, """@testitem "test_one" begin @test 1==1 end""")
        # First discover to get the node ID
        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]

        cmd = """{"command":"ingest","params":{"selected":["$(node_id)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        @test haskey(parsed, "result")
        @test haskey(parsed["result"], "edges")
    end
end

@testset "Ingest multiple items" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_multi.jl")
        write(test_file, """
        @testitem "item_a" begin @test 1==1 end
        @testitem "item_b" begin @test 2==2 end
        """)
        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        nodes = disc["result"]
        node_ids = [n["node_id"] for n in nodes]

        cmd = """{"command":"ingest","params":{"selected":$(JSON.json(node_ids))}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        @test haskey(parsed["result"], "edges")
    end
end

@testset "Ingest missing params" begin
    resp = Protocol.handle("""{"command":"ingest"}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("missing 'params'", parsed["error"]["message"])
end

@testset "Ingest missing selected" begin
    resp = Protocol.handle("""{"command":"ingest","params":{}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("selected", parsed["error"]["message"])
end

@testset "Ingest empty selected" begin
    resp = Protocol.handle("""{"command":"ingest","params":{"selected":[]}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("empty", parsed["error"]["message"])
end

@testset "Ingest invalid node ID format" begin
    resp = Protocol.handle("""{"command":"ingest","params":{"selected":["bad-format"]}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == true
    @test haskey(parsed["result"], "errors")
    @test length(parsed["result"]["errors"]) == 1
    @test parsed["result"]["errors"][1]["node_id"] == "bad-format"
    @test occursin("node ID", parsed["result"]["errors"][1]["error"])
end

# ── Ingest via run_output (TIA-ADAPT-008) ─────

@testset "Ingest via run_output returns runtime_edges" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_foo.jl")
        write(test_file, """@testitem "test_one" begin @test 1==1 end""")

        # Discover to get node ID
        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]

        run_output_lines = ["""{\"test_id\":\"$(node_id)\",\"outcome\":\"passed\"}"""]
        run_output_str = join(run_output_lines, "\n")

        # Build command via Dict to ensure proper JSON encoding
        cmd_dict = Dict(
            "command" => "ingest",
            "params" => Dict(
                "run_output" => run_output_str
            )
        )
        cmd = JSON.json(cmd_dict)
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        @test haskey(parsed, "result")
        @test haskey(parsed["result"], "runtime_edges")
        @test haskey(parsed["result"], "per_test_results")
        @test haskey(parsed["result"], "external_inputs")
        @test isa(parsed["result"]["runtime_edges"], Vector)
        @test isa(parsed["result"]["per_test_results"], Vector)
        @test isa(parsed["result"]["external_inputs"], Vector)
    end
end

@testset "Ingest via run_output: per_test_result matches input" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_bar.jl")
        write(test_file, """@testitem "bar" begin @test 1==1 end""")

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]

        run_output = """{\"test_id\":\"$(node_id)\",\"outcome\":\"passed\",\"duration_ms\":42,\"error_text\":null}"""

        cmd_dict = Dict(
            "command" => "ingest",
            "params" => Dict(
                "run_output" => run_output
            )
        )
        cmd = JSON.json(cmd_dict)
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        results = parsed["result"]["per_test_results"]
        @test length(results) == 1
        @test results[1]["test_id"] == node_id
        @test results[1]["outcome"] == "passed"
        @test results[1]["duration_ms"] == 42
    end
end

@testset "Ingest via run_output: runtime_edges have correct shape" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_edge_shape.jl")
        write(test_file, """@testitem "shape" begin @test 1==1 end""")

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]

        run_output = """{\"test_id\":\"$(node_id)\",\"outcome\":\"passed\"}"""

        cmd_dict = Dict(
            "command" => "ingest",
            "params" => Dict(
                "run_output" => run_output
            )
        )
        cmd = JSON.json(cmd_dict)
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        edges = parsed["result"]["runtime_edges"]

        for edge in edges
            @test haskey(edge, "from")
            @test haskey(edge, "to")
            @test haskey(edge, "weight")
            @test haskey(edge, "origin")
            @test edge["from"] == node_id
            @test edge["origin"] == "runtime"
            @test edge["weight"] == 1000000
        end
    end
end

@testset "Ingest via run_output: multiple test results" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_multi_run.jl")
        write(test_file, """
        @testitem "a" begin @test 1==1 end
        @testitem "b" begin @test 2==2 end
        """)

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        nodes = disc["result"]
        node_ids = [n["node_id"] for n in nodes]

        lines = ["""{\"test_id\":\"$(id)\",\"outcome\":\"passed\"}""" for id in node_ids]
        run_output_str = join(lines, "\n")

        cmd_dict = Dict(
            "command" => "ingest",
            "params" => Dict(
                "run_output" => run_output_str
            )
        )
        cmd = JSON.json(cmd_dict)
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        results = parsed["result"]["per_test_results"]
        @test length(results) == 2

        result_ids = [r["test_id"] for r in results]
        @test sort(result_ids) == sort(node_ids)

        edges = parsed["result"]["runtime_edges"]
    end
end

@testset "Ingest via run_output: empty run_output returns empty arrays" begin
    empty!(Protocol.session_coverage)

    cmd_dict = Dict(
        "command" => "ingest",
        "params" => Dict(
            "run_output" => ""
        )
    )
    cmd = JSON.json(cmd_dict)
    resp = Protocol.handle(cmd)
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    @test isempty(parsed["result"]["runtime_edges"])
    @test isempty(parsed["result"]["per_test_results"])
    @test isempty(parsed["result"]["external_inputs"])
end

@testset "Ingest via run_output: missing run_output errors" begin
    resp = Protocol.handle("""{"command":"ingest","params":{}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("run_output", parsed["error"]["message"])
end

@testset "Ingest via run_output: malformed JSON line errors" begin
    cmd_dict = Dict(
        "command" => "ingest",
        "params" => Dict(
            "run_output" => "not json"
        )
    )
    cmd = JSON.json(cmd_dict)
    resp = Protocol.handle(cmd)
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("run_output", parsed["error"]["message"])
end

# ── Static-deps handler (PROTO-005) ───────────

@testset "Static-deps unresolved when no coverage recorded" begin
    # Clear any session state from previous tests
    empty!(Protocol.session_coverage)

    resp = Protocol.handle("""{"command":"static-deps","params":{"changed_files":["src/foo.jl"]}}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    @test haskey(parsed["result"], "edges")
    @test parsed["result"]["edges"]["src/foo.jl"] == "unresolved"
end

@testset "Static-deps multiple files all unresolved" begin
    empty!(Protocol.session_coverage)

    cmd = """{"command":"static-deps","params":{"changed_files":["a.jl","b.jl","c.jl"]}}"""
    resp = Protocol.handle(cmd)
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    edges = parsed["result"]["edges"]
    @test length(edges) == 3
    @test edges["a.jl"] == "unresolved"
    @test edges["b.jl"] == "unresolved"
    @test edges["c.jl"] == "unresolved"
end

@testset "Static-deps missing params" begin
    resp = Protocol.handle("""{"command":"static-deps"}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("missing 'params'", parsed["error"]["message"])
end

@testset "Static-deps missing changed_files" begin
    resp = Protocol.handle("""{"command":"static-deps","params":{}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("changed_files", parsed["error"]["message"])
end

@testset "Static-deps empty changed_files" begin
    resp = Protocol.handle("""{"command":"static-deps","params":{"changed_files":[]}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == true
    @test parsed["result"]["edges"] == Dict{String, Any}()
end

@testset "Static-deps with prior ingest returns edges not unresolved" begin
    empty!(Protocol.session_coverage)

    mktempdir() do dir
        test_file = joinpath(dir, "test_edgy.jl")
        write(test_file, """@testitem "edgy" begin @test 1==1 end""")

        # Discover to get node ID
        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]
        abs_file = disc["result"][1]["file"]

        # Ingest to populate session_coverage
        ingest_cmd = """{"command":"ingest","params":{"selected":["$(node_id)"]}}"""
        Protocol.handle(ingest_cmd)

        # Now static-deps should find edges for this file
        sd_cmd = """{"command":"static-deps","params":{"changed_files":["$(abs_file)"]}}"""
        sd_resp = Protocol.handle(sd_cmd)
        sd = JSON.parse(sd_resp)

        @test sd["ok"] == true
        @test haskey(sd["result"]["edges"], abs_file)
        # The file should NOT be "unresolved" — should be a dict (even if empty)
        @test !isa(sd["result"]["edges"][abs_file], String)  # not "unresolved"
        @test isa(sd["result"]["edges"][abs_file], AbstractDict)  # edges dict
    end
end

@testset "Static-deps mixed: some covered, some unresolved" begin
    empty!(Protocol.session_coverage)

    mktempdir() do dir
        test_file = joinpath(dir, "covered.jl")
        write(test_file, """@testitem "c" begin @test 1==1 end""")

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]
        abs_file = disc["result"][1]["file"]

        # Ingest one file
        ingest_cmd = """{"command":"ingest","params":{"selected":["$(node_id)"]}}"""
        Protocol.handle(ingest_cmd)

        # static-deps with both covered and uncovered file
        sd_cmd = """{"command":"static-deps","params":{"changed_files":["$(abs_file)","other.jl"]}}"""
        sd_resp = Protocol.handle(sd_cmd)
        sd = JSON.parse(sd_resp)

        @test sd["ok"] == true
        edges = sd["result"]["edges"]
        @test length(edges) == 2
        @test haskey(edges, abs_file)
        @test haskey(edges, "other.jl")
        @test !isa(edges[abs_file], String)  # not "unresolved"
        @test isa(edges[abs_file], AbstractDict)  # covered → edges dict
        @test edges["other.jl"] == "unresolved"  # unknown → unresolved
    end
end

# ── @testset discovery (Base.Test support) ────

@testset "Discover: @testset returns suite_kind Base.Test" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_foo.jl")
        write(test_file, """
        @testset "My Suite" begin
            @test 1 == 1
        end
        """)
        cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test length(nodes) == 1
        @test nodes[1]["suite_kind"] == "Base.Test"
        @test nodes[1]["file"] == realpath(test_file)
        @test occursin(":", nodes[1]["node_id"])
    end
end

@testset "Discover: unnamed @testset begin" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_no_name.jl")
        write(test_file, """
        @testset begin
            @test 1 == 1
        end
        """)
        cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test length(nodes) == 1
        @test nodes[1]["suite_kind"] == "Base.Test"
    end
end

@testset "Discover: mixed @testitem and @testset" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_mixed.jl")
        write(test_file, """
        @testitem "unit" begin
            @test 1 == 1
        end

        @testset "Integration" begin
            @test 2 == 2
        end
        """)
        cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test length(nodes) == 2
        kinds = [n["suite_kind"] for n in nodes]
        @test "ReTestItems.jl" in kinds
        @test "Base.Test" in kinds
    end
end

@testset "Discover: file-level fallback for plain test files" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_plain.jl")
        write(test_file, """
        @test 1 == 1
        @test 2 == 2
        """)
        cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test length(nodes) == 1
        @test nodes[1]["suite_kind"] == "Base.Test"
        @test nodes[1]["file"] == realpath(test_file)
        # File-level fallback has node_id ending in ":0"
        @test endswith(nodes[1]["node_id"], ":0")
    end
end

@testset "Discover: file-level fallback only for .jl files with no test blocks" begin
    mktempdir() do dir
        # File with @testitem — no fallback
        with_item = joinpath(dir, "with_item.jl")
        write(with_item, """@testitem "a" begin @test 1==1 end""")

        # File with @testset — no fallback
        with_set = joinpath(dir, "with_set.jl")
        write(with_set, """@testset "B" begin @test 2==2 end""")

        # Plain file — should get fallback
        plain = joinpath(dir, "plain.jl")
        write(plain, """@test 3 == 3""")

        cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test length(nodes) == 3

        # Check kinds
        kinds = [n["suite_kind"] for n in nodes]
        @test count(k -> k == "ReTestItems.jl", kinds) == 1
        @test count(k -> k == "Base.Test", kinds) == 2
    end
end

# ── @testset run-args (Base.Test support) ────

@testset "Run-args: @testset item emits include()" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_set.jl")
        write(test_file, """
        @testset "My Suite" begin
            @test 1 == 1
        end
        """)

        # Discover to get the node_id
        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]

        # Run-args
        cmd = """{"command":"run-args","params":{"selected":["$(node_id)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        result = parsed["result"]
        @test haskey(result, "runner_args")
        @test haskey(result, "collection_path")
        @test result["runner_args"][1] == "julia"
        @test result["runner_args"][2] == "--project=."
        @test result["runner_args"][3] == "-e"
        # Should contain include() for the test file, not ReTestItems
        @test occursin("include", result["runner_args"][4])
        @test occursin(test_file, result["runner_args"][4])
    end
end

@testset "Run-args: file-level fallback emits include()" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_plain.jl")
        write(test_file, """@test 1 == 1""")

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]

        cmd = """{"command":"run-args","params":{"selected":["$(node_id)"]}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        result = parsed["result"]
        @test occursin("include", result["runner_args"][4])
        @test occursin(test_file, result["runner_args"][4])
    end
end

@testset "Run-args: mixed @testitem and @testset uses include()" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_mixed.jl")
        write(test_file, """
        @testitem "unit" begin
            @test 1 == 1
        end

        @testset "Integration" begin
            @test 2 == 2
        end
        """)

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        nodes = disc["result"]
        node_ids = [n["node_id"] for n in nodes]
        @test length(node_ids) == 2

        # Run-args with both items
        cmd = """{"command":"run-args","params":{"selected":$(JSON.json(node_ids))}}"""
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        result = parsed["result"]
        # Mixed types should use include()
        @test occursin("include", result["runner_args"][4])
        @test occursin(test_file, result["runner_args"][4])
    end
end
