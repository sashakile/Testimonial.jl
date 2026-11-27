# Protocol adapter tests: static-deps handler (PROTO-005) and the
# protocol response schema contract (testimonial-nl2b.2).

using Testimonial
using Testimonial.Protocol
using Test
using JSON
using SHA
using TOML
using Dates
using Serialization


# ── Static-deps handler (PROTO-005) ───────────

@testset "Static-deps empty when no coverage recorded" begin
    # Clear any session state from previous tests
    empty!(Protocol.session_coverage)
    empty!(Protocol.session_static_edges)

    resp = Protocol.handle("""{"command":"static-deps","params":{"changed_files":["src/foo.jl"]}}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    @test haskey(parsed["result"], "edges")
    @test parsed["result"]["edges"] == []
end

@testset "Static-deps multiple files empty when no coverage" begin
    empty!(Protocol.session_coverage)
    empty!(Protocol.session_static_edges)

    cmd = """{"command":"static-deps","params":{"changed_files":["a.jl","b.jl","c.jl"]}}"""
    resp = Protocol.handle(cmd)
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    edges = parsed["result"]["edges"]
    @test length(edges) == 0
    @test edges == []
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
    @test parsed["result"]["edges"] == []
end

@testset "Static-deps with prior ingest returns DepEdge array" begin
    empty!(Protocol.session_coverage)
    empty!(Protocol.session_static_edges)

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

        # Now static-deps should find DepEdge entries for this file
        sd_cmd = """{"command":"static-deps","params":{"changed_files":["$(abs_file)"]}}"""
        sd_resp = Protocol.handle(sd_cmd)
        sd = JSON.parse(sd_resp)

        @test sd["ok"] == true
        @test haskey(sd["result"], "edges")
        edges = sd["result"]["edges"]
        @test length(edges) > 0
        # Each edge should be a DepEdge dict with from, to, weight, origin
        found_edge = false
        for edge in edges
            if edge["to"] == abs_file
                found_edge = true
                @test haskey(edge, "from")
                @test haskey(edge, "weight")
                @test edge["origin"] == "static"
            end
        end
        @test found_edge
    end
end

@testset "Static-deps mixed: covered file returns edges, unknown file omitted" begin
    empty!(Protocol.session_coverage)
    empty!(Protocol.session_static_edges)

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
        # Should have edges for the covered file but not the unknown one
        @test length(edges) >= 1
        covered_edges = filter(e -> e["to"] == abs_file, edges)
        @test length(covered_edges) >= 1
        for edge in covered_edges
            @test haskey(edge, "from")
            @test haskey(edge, "weight")
            @test edge["origin"] == "static"
        end
        unknown_edges = filter(e -> e["to"] == "other.jl", edges)
        @test isempty(unknown_edges)
    end
end

@testset "Static-deps uses static edges from CoverageIndex when no session coverage" begin
    empty!(Protocol.session_coverage)
    empty!(Protocol.session_static_edges)

    mktempdir() do dir
        test_file = joinpath(dir, "test_foo.jl")
        write(test_file, """@testitem "test_a" begin @test 1==1 end""")

        # Create a CoverageIndex with static_edges
        ref = Testimonial.TestItemRef(test_file, 1, "test_a")
        ic = Testimonial.ItemCoverage(ref, [1, 2, 3], Int[], Dict())
        items = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(ref => ic)

        static_edges = Dict{String, Set{Testimonial.TestItemRef}}(
            "src/lib.jl" => Set([ref]),
        )

        index = Testimonial.CoverageIndex(
            items,
            "abc1234",
            string(VERSION),
            v"0.1.0",
            now(),
            "",
            Dict{String, Set{String}}(),
            Dict{Testimonial.TestItemRef, Vector{Tuple{String, Int}}}(),
            Dict{Testimonial.TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(),
            static_edges,
            Dict{Symbol, Any}(),
            0, 0, 1,
        )

        # Save index to disk
        testimonial_dir = joinpath(dir, ".testimonial")
        mkpath(testimonial_dir)
        index_path = joinpath(testimonial_dir, "index.jls")
        open(index_path, "w") do io
            serialize(io, index)
        end

        # Change to the temp dir so _ensure_session_static_edges_loaded can find the index
        orig_dir = pwd()
        cd(dir)
        try
            # static-deps with no session coverage should use static edges
            sd_cmd = """{"command":"static-deps","params":{"changed_files":["src/lib.jl"]}}"""
            sd_resp = Protocol.handle(sd_cmd)
            sd = JSON.parse(sd_resp)

            @test sd["ok"] == true
            @test haskey(sd["result"], "edges")
            edges = sd["result"]["edges"]
            @test length(edges) > 0

            # Should find an edge from the static analysis
            found_static_edge = false
            for edge in edges
                if edge["origin"] == "static" && endswith(edge["to"], "src/lib.jl")
                    found_static_edge = true
                    @test edge["from"] == "$(test_file):1"
                    @test edge["weight"] == 1_000_000
                end
            end
            @test found_static_edge
        finally
            cd(orig_dir)
        end
    end
end

@testset "Static-deps falls back to unresolved when no static data exists" begin
    empty!(Protocol.session_coverage)
    empty!(Protocol.session_static_edges)

    # No index file exists — should return empty edges (unresolved fallback)
    sd_cmd = """{"command":"static-deps","params":{"changed_files":["src/unknown.jl"]}}"""
    sd_resp = Protocol.handle(sd_cmd)
    sd = JSON.parse(sd_resp)

    @test sd["ok"] == true
    @test haskey(sd["result"], "edges")
    @test isempty(sd["result"]["edges"])
end

# ── Protocol response schema contract (testimonial-nl2b.2) ─
# The static-deps regression (commit 6a7a832) switched `static-deps` from a
# file→"unresolved" map to the standard DepEdge array. These contract tests
# pin the documented schema so the contract cannot silently drift again.
# The canonical field set is declared once in `Protocol.DEPEDGE_FIELDS`.

@testset "Protocol schema: DEPEDGE_FIELDS is declared" begin
    @test isdefined(Protocol, :DEPEDGE_FIELDS)
    @test issetequal(Protocol.DEPEDGE_FIELDS, ["from", "to", "weight", "origin"])
end

@testset "Protocol schema: static-deps envelope shape" begin
    empty!(Protocol.session_coverage)
    empty!(Protocol.session_static_edges)

    # No-coverage / unresolved fallback: edges is an empty array (NOT a map)
    resp = Protocol.handle("""{"command":"static-deps","params":{"changed_files":["src/unknown.jl"]}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == true
    @test parsed["result"] isa AbstractDict
    @test Set(keys(parsed["result"])) == Set(["edges"])
    @test parsed["result"]["edges"] isa Vector
    @test isempty(parsed["result"]["edges"])
end

@testset "Protocol schema: every static-deps edge matches DEPEDGE_FIELDS exactly" begin
    empty!(Protocol.session_coverage)
    empty!(Protocol.session_static_edges)

    mktempdir() do dir
        test_file = joinpath(dir, "test_schema.jl")
        write(test_file, """@testitem \"schema\" begin @test 1==1 end""")

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]
        abs_file = disc["result"][1]["file"]

        # Ingest to populate session_coverage
        Protocol.handle("""{"command":"ingest","params":{"selected":["$(node_id)"]}}""")

        sd_resp = Protocol.handle("""{"command":"static-deps","params":{"changed_files":["$(abs_file)"]}}""")
        sd = JSON.parse(sd_resp)
        @test sd["ok"] == true
        @test sd["result"]["edges"] isa AbstractVector
        @test !isempty(sd["result"]["edges"])

        for edge in sd["result"]["edges"]
            @test Set(keys(edge)) == Set(Protocol.DEPEDGE_FIELDS)
            @test edge["from"] isa String
            @test edge["to"] isa String
            @test edge["weight"] isa Number
            @test edge["origin"] == "static"
        end
    end
end

@testset "Protocol schema: ingest run_output edges are DepEdge arrays" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_inf_schema.jl")
        write(test_file, """@testitem \"inf_schema\" begin @test 1==1 end""")

        disc_cmd = """{"command":"discover","params":{"test_directories":["$(dir)"]}}"""
        disc_resp = Protocol.handle(disc_cmd)
        disc = JSON.parse(disc_resp)
        node_id = disc["result"][1]["node_id"]

        run_output = """{\"test_id\":\"$(node_id)\",\"outcome\":\"passed\"}"""
        cmd_dict = Dict("command" => "ingest", "params" => Dict("run_output" => run_output))
        resp = Protocol.handle(JSON.json(cmd_dict))
        parsed = JSON.parse(resp)
        @test parsed["ok"] == true
        @test parsed["result"] isa AbstractDict

        # inference_edges must conform to DEPEDGE_FIELDS (when non-empty)
        @test haskey(parsed["result"], "inference_edges")
        inf_arr = parsed["result"]["inference_edges"]
        @test inf_arr isa AbstractVector
        for edge in inf_arr
            @test Set(keys(edge)) == Set(Protocol.DEPEDGE_FIELDS)
            @test edge["origin"] == "inference"
        end

        # runtime_edges, when present and non-empty, must also conform
        if haskey(parsed["result"], "runtime_edges")
            rt_arr = parsed["result"]["runtime_edges"]
            @test rt_arr isa AbstractVector
            for edge in rt_arr
                @test Set(keys(edge)) == Set(Protocol.DEPEDGE_FIELDS)
                @test edge["origin"] == "runtime"
            end
        end
    end
end
