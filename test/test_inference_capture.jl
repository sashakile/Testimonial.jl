# Testimonial.jl — Tests for inference trace capture in the subprocess driver
#
# Verifies that driver.jl wraps @testitem execution with SnoopCompile's
# @snoop_inference and writes an inference trace sidecar alongside the
# coverage artifacts. The sidecar is consumed by the inference-layer
# parser (testimonial-be7o) to populate CoverageIndex.inference_edges.
#
# See openspec/project.md — inference-layer capability (Phase 2).
# Ref: testimonial-1v4f

using Testimonial
using Test
using Serialization

# ── Helpers ───────────────────────────────────

"""Create a minimal scratch Julia package in `dir` for ReTestItems."""
function _create_inference_scratch(dir::String)
    write(joinpath(dir, "Project.toml"), """
    name = "ScratchInferencePkg"
    uuid = "00000000-0000-0000-0000-000000000010"
    """)
    src_dir = joinpath(dir, "src")
    mkpath(src_dir)
    write(joinpath(src_dir, "ScratchInferencePkg.jl"), """
    module ScratchInferencePkg
    greet() = "hello"
    end
    """)
    test_dir = joinpath(dir, "test")
    mkpath(test_dir)
    return test_dir
end

# ── Inference trace sidecar ───────────────────

@testset "driver.jl produces an inference trace sidecar" begin
    mktempdir() do project_dir
        test_dir = _create_inference_scratch(project_dir)
        test_file = joinpath(test_dir, "inference_capture_test.jl")
        # Define a fresh function inside the testitem to guarantee that
        # @snoop_inference has at least one method to infer.
        write(test_file, """
        @testitem "snoop_capture" begin
            f(x) = x * 2
            @test f(21) == 42
        end
        """)

        cmd, env = Testimonial.build_driver_command(test_file, "snoop_capture")
        # Run the driver directly in an isolated cwd so the sidecar lands
        # there and is not cleaned up by record_item's _collect_coverage.
        cwd = mktempdir()
        run(setenv(Cmd(cmd), merge(ENV, env); dir=cwd))

        trace_path = joinpath(cwd, "inference_trace.jls")
        @test isfile(trace_path)
        @test filesize(trace_path) > 0
    end
end

@testset "inference trace sidecar deserializes to caller/callee edges" begin
    mktempdir() do project_dir
        test_dir = _create_inference_scratch(project_dir)
        test_file = joinpath(test_dir, "inference_deser_test.jl")
        write(test_file, """
        @testitem "snoop_deser" begin
            f(x) = x + 1
            g() = f(42)
            @test g() == 43
        end
        """)

        cmd, env = Testimonial.build_driver_command(test_file, "snoop_deser")
        cwd = mktempdir()
        run(setenv(Cmd(cmd), merge(ENV, env); dir=cwd))

        trace_path = joinpath(cwd, "inference_trace.jls")
        @test isfile(trace_path)

        edges = Serialization.deserialize(trace_path)
        @test edges isa Vector
        # The testitem defines two fresh methods (f, g) where g calls f,
        # so at least one caller→callee edge should have been captured.
        @test !isempty(edges)
    end
end
