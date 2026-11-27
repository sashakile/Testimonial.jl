# Protocol adapter tests: run-args handler (PROTO-007), incl. @testset run-args.

using Testimonial
using Testimonial.Protocol
using Test
using JSON
using SHA
using TOML
using Dates
using Serialization

# ── Run-args handler (PROTO-007) ───────────────

@testset "Run-args single test item" begin
    resp = Protocol.handle("""{"command":"run-args","params":{"selected":["test/test_foo.jl:test_bar"]}}""")
    parsed = JSON.parse(resp)

    @test parsed["ok"] == true
    result = parsed["result"]
    @test haskey(result, "runner_args")
    @test haskey(result, "collection_path")
    @test result["runner_args"][1] == "julia"
    # The runner is invoked with a provisioned test env, not the bare cwd project
    @test startswith(result["runner_args"][2], "--project=")
    @test result["runner_args"][2] != "--project=."
    @test result["runner_args"][3] == "-e"
    # ReTestItems.runtests with a positional path filter and name= regex —
    # the installed ReTestItems rejects files=/names= kwargs.
    expr = result["runner_args"][4]
    @test occursin("ReTestItems.runtests(", expr)
    @test occursin("\"test/test_foo.jl\"", expr)
    @test occursin("name=r\"^(test_bar)\$\"", expr)
    @test !occursin("files=", expr)
    @test !occursin("names=", expr)
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

@testset "Run-args: testitem at line resolves the item name" begin
    mktempdir() do dir
        test_file = joinpath(dir, "alpha_test.jl")
        write(test_file, """
        @testitem "alpha one" begin
            @test true
        end
        """)

        disc_resp = Protocol.handle("""{"command":"discover","params":{"test_directories":["$(dir)"]}}""")
        node_id = JSON.parse(disc_resp)["result"][1]["node_id"]

        resp = Protocol.handle("""{"command":"run-args","params":{"selected":["$(node_id)"]}}""")
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        expr = parsed["result"]["runner_args"][4]
        # The name= filter must match the @testitem NAME, not the line number
        @test occursin("name=r\"^(alpha one)\$\"", expr)
        @test occursin("\"$(test_file)\"", expr)
    end
end

@testset "Run-args: multiple items in one file combine into one name regex" begin
    mktempdir() do dir
        test_file = joinpath(dir, "alpha_test.jl")
        write(test_file, """
        @testitem "alpha one" begin
            @test true
        end
        @testitem "beta two" begin
            @test true
        end
        """)

        disc_resp = Protocol.handle("""{"command":"discover","params":{"test_directories":["$(dir)"]}}""")
        node_ids = [n["node_id"] for n in JSON.parse(disc_resp)["result"]]

        resp = Protocol.handle("""{"command":"run-args","params":{"selected":$(JSON.json(node_ids))}}""")
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        expr = parsed["result"]["runner_args"][4]
        @test occursin("name=r\"^(alpha one|beta two)\$\"", expr)
    end
end

@testset "Run-args provisions a Pkg.test-style test env for [targets.test] deps" begin
    mktempdir() do dir
        # Scratch project whose test target depends on an extra NOT in the
        # main [deps] — the provisioned env must contain it.
        write(joinpath(dir, "Project.toml"), """
        name = "ScratchRti"
        uuid = "00000000-0000-0000-0000-0000000009aa"
        version = "0.1.0"

        [extras]
        Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

        [targets]
        test = ["Random"]
        """)
        mkpath(joinpath(dir, "src"))
        write(joinpath(dir, "src", "ScratchRti.jl"), "module ScratchRti end\n")
        mkpath(joinpath(dir, "tests"))
        test_file = joinpath(dir, "tests", "alpha_test.jl")
        write(test_file, """@testitem "alpha one" begin @test true end""")

        resp = cd(dir) do
            Protocol.handle("""{"command":"run-args","params":{"selected":["$(test_file):1"]}}""")
        end
        parsed = JSON.parse(resp)

        @test parsed["ok"] == true
        runner_args = parsed["result"]["runner_args"]
        @test startswith(runner_args[2], "--project=")
        env_dir = replace(runner_args[2], "--project=" => "")
        # The provisioned env exists and declares the target dep + ReTestItems
        @test isdir(env_dir)
        env_project = TOML.parsefile(joinpath(env_dir, "Project.toml"))
        deps = get(env_project, "deps", Dict{String, Any}())
        @test haskey(deps, "Random")        # [targets.test] extra provisioned
        @test haskey(deps, "ReTestItems")   # runner dependency provisioned
        @test haskey(deps, "ScratchRti")    # the package itself developed in
    end
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
        @test startswith(result["runner_args"][2], "--project=")
        @test result["runner_args"][2] != "--project=."
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
