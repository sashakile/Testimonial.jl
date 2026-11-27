# Protocol adapter tests: discover handler (PROTO-003), incl. project-scope
# regressions (testaruda-pevk) and @testset discovery support.

using Testimonial
using Testimonial.Protocol
using Test
using JSON
using SHA
using TOML
using Dates
using Serialization

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

# ── Discover default regression tests ──────────
# These verify that discover without params resolves to pwd()/test/ (external
# adapter mode) rather than always using @__DIR__/../test/ (which would point
# to Testimonial.jl's own tests regardless of cwd).

@testset "Discover defaults to pwd()/test/ when cwd is external project" begin
    mktempdir() do dir
        # Create an external project with a test/ dir
        test_dir = joinpath(dir, "test")
        mkpath(test_dir)
        test_file = joinpath(test_dir, "test_ext.jl")
        write(test_file, """@testitem "external_only" begin @test 1==1 end""")

        # cd into the external project and call discover without params
        cd(dir) do
            resp = Protocol.handle("""{"command":"discover"}""")
            parsed = JSON.parse(resp)

            @test parsed["ok"] == true
            nodes = parsed["result"]
            @test length(nodes) == 1
            @test nodes[1]["file"] == realpath(test_file)
            @test nodes[1]["suite_kind"] == "ReTestItems.jl"
        end
    end
end

@testset "Discover from external project does NOT return Testimonial tests" begin
    mktempdir() do dir
        # Create an external project with a test that has a unique name
        test_dir = joinpath(dir, "test")
        mkpath(test_dir)
        write(joinpath(test_dir, "test_ext.jl"), """@testitem "should_not_be_present_internal" begin @test 1==1 end""")

        cd(dir) do
            resp = Protocol.handle("""{"command":"discover"}""")
            parsed = JSON.parse(resp)

            @test parsed["ok"] == true
            nodes = parsed["result"]

            # Every returned file should be under our temporary dir, NOT Testimonial.jl
            for node in nodes
                @test startswith(node["file"], dir)
            end

            # Should find exactly our test
            @test length(nodes) == 1
        end
    end
end

@testset "Discover from external project without test/ returns empty result" begin
    mktempdir() do dir
        # Create an external project WITHOUT a test/ or tests/ directory.
        # Discovery must stay within the invoking project scope (testaruda-pevk)
        # and return an empty — valid — result, never fall back to
        # @__DIR__/../test/ (Testimonial.jl's own tests).
        cd(dir) do
            resp = Protocol.handle("""{"command":"discover"}""")
            parsed = JSON.parse(resp)

            # Empty discovery result is a valid outcome
            @test parsed["ok"] == true
            nodes = parsed["result"]
            @test isempty(nodes)
        end
    end
end

@testset "Discover with explicit test_directories still works from any cwd" begin
    mktempdir() do dir
        test_dir = joinpath(dir, "mytests")
        mkpath(test_dir)
        test_file = joinpath(test_dir, "test_explicit.jl")
        write(test_file, """@testitem "explicit_dir" begin @test 1==1 end""")

        # Even from a different cwd, explicit test_directories should work
        mktempdir() do other_dir
            cd(other_dir) do
                cmd = """{"command":"discover","params":{"test_directories":["$(test_dir)"]}}"""
                resp = Protocol.handle(cmd)
                parsed = JSON.parse(resp)

                @test parsed["ok"] == true
                nodes = parsed["result"]
                @test length(nodes) == 1
                @test nodes[1]["file"] == realpath(test_file)
            end
        end
    end
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

@testset "Discover rejects nonexistent explicit project_root" begin
    # A present-but-invalid project_root must hard-error, never silently
    # resolve to a different (pwd-based) scope — silent wrong-scope
    # discovery with ok=true is the failure mode testaruda-pevk exists to
    # prevent (review CORR-001).
    resp = Protocol.handle("""{"command":"discover","params":{"project_root":"/nonexistent/project"}}""")
    parsed = JSON.parse(resp)
    @test parsed["ok"] == false
    @test occursin("project_root", parsed["error"]["message"])
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
