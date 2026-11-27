# Testimonial.jl — Subprocess regression test: discover stays within the
# invoking project (testaruda-pevk).
#
# When the adapter was invoked from a project that has `tests/` but no
# `test/` (e.g. the testaruda repo itself), discovery fell back past
# `pwd()/test` to the ADAPTER INSTALLATION's test directory, returning
# Testimonial.jl's own test items with absolute paths pointing into the
# adapter's install tree.
#
# These tests spawn the real protocol adapter (`run_adapter_protocol`) as a
# Julia subprocess with the cwd set to a temp project WITHOUT `test/` and
# assert that NO external paths are returned.

using Testimonial
using Testimonial.Protocol
using Test
using JSON

_pkg_root() = realpath(pkgdir(Testimonial))

"""
    _run_adapter_subprocess(cwd, lines) -> Vector{String}

Spawn the adapter protocol loop in a real Julia subprocess with `cwd` as the
working directory, feed the given JSON command lines on stdin, and return
one response line per command.
"""
function _run_adapter_subprocess(cwd::AbstractString, lines::Vector{String})
    pkg_root = _pkg_root()
    cmd = `julia --project=$pkg_root -e 'using Testimonial; Testimonial.Protocol.run_adapter_protocol()'`
    responses = String[]
    open(setenv(cmd; dir=String(cwd)), "r+") do io
        for line in lines
            println(io, line)
        end
        flush(io)
        for _ in 1:length(lines)
            push!(responses, readline(io))
        end
    end
    return responses
end

@testset "Discover subprocess: project with tests/ but no test/ returns only local items" begin
    mktempdir() do proj
        mkpath(joinpath(proj, "tests"))
        write(joinpath(proj, "tests", "alpha_test.jl"),
              "@testitem \"local_scope_guard\" begin @test true end\n")

        # The adapter installation's own test dir — must NOT leak into results
        install_test_dir = joinpath(_pkg_root(), "test")
        @test isdir(install_test_dir)

        responses = _run_adapter_subprocess(proj, [
            """{"command":"handshake"}""",
            """{"command":"discover"}""",
        ])
        handshake = JSON.parse(responses[1])
        @test handshake["ok"] == true

        parsed = JSON.parse(responses[2])
        @test parsed["ok"] == true
        nodes = parsed["result"]

        # NO external paths — every returned file must live in the temp project
        scope = realpath(proj)
        for node in nodes
            @test startswith(node["file"], scope)
            @test !startswith(node["file"], install_test_dir)
        end

        # And the local item IS discovered (`tests/` is an acceptable root)
        @test length(nodes) == 1
        @test endswith(nodes[1]["file"], "alpha_test.jl")
        @test occursin("local_scope_guard", nodes[1]["node_id"]) || endswith(nodes[1]["node_id"], ":1")
    end
end

@testset "Discover subprocess: project without test dirs returns empty result" begin
    mktempdir() do proj
        # Neither test/ nor tests/ — empty discovery is a valid outcome, not
        # an error, and must not fall back to the adapter installation.
        responses = _run_adapter_subprocess(proj, ["""{"command":"discover"}"""])
        parsed = JSON.parse(responses[1])
        @test parsed["ok"] == true
        @test isempty(parsed["result"])
    end
end

@testset "Discover subprocess: explicit test_directories respected within project" begin
    mktempdir() do proj
        # Project has a test/ dir; explicit params still scope discovery there
        test_dir = joinpath(proj, "test")
        mkpath(test_dir)
        write(joinpath(test_dir, "beta_test.jl"),
              "@testitem \"explicit_dir_item\" begin @test true end\n")

        responses = _run_adapter_subprocess(proj, [
            """{"command":"discover","params":{"test_directories":["$(test_dir)"]}}""",
        ])
        parsed = JSON.parse(responses[1])
        @test parsed["ok"] == true
        nodes = parsed["result"]
        @test length(nodes) == 1
        @test startswith(nodes[1]["file"], realpath(proj))
    end
end
