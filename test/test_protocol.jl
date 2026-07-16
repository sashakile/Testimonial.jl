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
        nodes = parsed["result"]["nodes"]
        @test length(nodes) == 2

        # Both nodes should have the same file (absolute)
        @test nodes[1]["file"] == realpath(test_file)
        @test nodes[2]["file"] == realpath(test_file)

        @test nodes[1]["name"] == "test_one"
        @test nodes[2]["name"] == "test_two"

        # Node IDs should be file:line format
        @test occursin("test_foo.jl:", nodes[1]["id"])
        @test occursin("test_foo.jl:", nodes[2]["id"])
        @test nodes[1]["id"] != nodes[2]["id"]
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
        nodes = parsed["result"]["nodes"]
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
        nodes = parsed["result"]["nodes"]
        @test isempty(nodes)
    end
end

@testset "Discover empty test_directories list" begin
    resp = Protocol.handle("""{"command":"discover","params":{"test_directories":[]}}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    nodes = parsed["result"]["nodes"]
    @test isempty(nodes)
end

@testset "Discover missing params" begin
    resp = Protocol.handle("""{"command":"discover"}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("missing 'params'", parsed["error"]["message"])
end

@testset "Discover missing test_directories" begin
    resp = Protocol.handle("""{"command":"discover","params":{}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("test_directories", parsed["error"]["message"])
end

@testset "Discover non-existent directory" begin
    resp = Protocol.handle("""{"command":"discover","params":{"test_directories":["/nonexistent/path"]}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("not a directory", parsed["error"]["message"])
end
