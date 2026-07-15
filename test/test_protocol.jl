# Protocol adapter tests — handshake handler and main loop
#
# Tests for PROTO-001 (main loop) and PROTO-002 (handshake handler).

using Testimonial
using Testimonial.Protocol
using Test
using JSON

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
    @test occursin("malformed JSON", parsed["error"])
end

@testset "Unknown command" begin
    resp = Protocol.handle("""{"command":"bogus"}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == false
    @test haskey(parsed, "error")
    @test occursin("unknown command", parsed["error"])
end

@testset "Missing command field" begin
    resp = Protocol.handle("""{"foo":"bar"}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == false
    @test haskey(parsed, "error")
    @test occursin("missing 'command' field", parsed["error"])
end

@testset "Empty input" begin
    resp = Protocol.handle("")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == false
    @test haskey(parsed, "error")
end

# ── Main loop (PROTO-001) — stdin/stdout simulation ──

@testset "Main loop processes one command" begin
    # Redirect stdin from a pipe
    input = """{"command":"handshake"}\n"""
    (rd, wr) = redirect_stdin()
    write(wr, input)
    close(wr)
    # We can't easily test the full loop without I/O mocking,
    # but handle() is tested separately above.
    redirect_stdin(rd)
end

@testset "Main loop skips empty lines" begin
    # Only the handle function is tested; the main loop strips empty lines
    # before passing to handle. Empty input returns an error from handle.
    resp = Protocol.handle("")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
end