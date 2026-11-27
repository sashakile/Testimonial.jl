# Protocol adapter tests: ingest handler (PROTO-004), run_output and
# inference edges (TIA-ADAPT-008).

using Testimonial
using Testimonial.Protocol
using Test
using JSON
using SHA
using TOML
using Dates
using Serialization

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

# ── Inference edges in ingest response ───────

@testset "Ingest response includes inference_edges field" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_inf.jl")
        write(test_file, """@testitem "inf" begin @test 1==1 end""")

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]

        run_output = """{\"test_id\":\"$(node_id)\",\"outcome\":\"passed\"}"""
        cmd_dict = Dict(
            "command" => "ingest",
            "params" => Dict("run_output" => run_output)
        )
        cmd = JSON.json(cmd_dict)
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        @test haskey(parsed["result"], "inference_edges")
        @test isa(parsed["result"]["inference_edges"], Vector)
    end
end

@testset "Ingest inference_edges has DepEdge format" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_inf2.jl")
        write(test_file, """@testitem "inf2" begin @test 1==1 end""")

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]

        run_output = """{\"test_id\":\"$(node_id)\",\"outcome\":\"passed\"}"""
        cmd_dict = Dict(
            "command" => "ingest",
            "params" => Dict("run_output" => run_output)
        )
        cmd = JSON.json(cmd_dict)
        resp = Protocol.handle(cmd)
        parsed = JSON.parse(resp)

        edges = parsed["result"]["inference_edges"]
        for edge in edges
            @test haskey(edge, "from")
            @test haskey(edge, "to")
            @test haskey(edge, "weight")
            @test haskey(edge, "origin")
            @test edge["origin"] == "inference"
        end
    end
end
