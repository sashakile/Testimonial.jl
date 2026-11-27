# Protocol adapter tests: stdin/stdout protocol loop integration.

using Testimonial
using Testimonial.Protocol
using Test
using JSON
using SHA
using TOML
using Dates
using Serialization


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

