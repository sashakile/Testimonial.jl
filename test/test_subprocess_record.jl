# Testimonial.jl — Integration test for record_item with SubprocessRunner
#
# Verifies that record_item spawns a real subprocess via SubprocessRunner,
# runs the @testitem through the TestimonialRunner driver, and returns
# an ItemCoverage result.
#
# Test files must be within a proper Julia project (ReTestItems requires it).
# We create a scratch project in a temp directory.
#
# See REC-002 (Subprocess invocation) and task testimonial-e47 in
# openspec/changes/implement-coverage-layer/tasks.md

using Testimonial
using Test

# ── Helpers ───────────────────────────────────

"""Create a minimal scratch Julia package in `dir` for ReTestItems."""
function create_scratch_project(dir::String)
    write(joinpath(dir, "Project.toml"), """
    name = "ScratchPkg"
    uuid = "00000000-0000-0000-0000-000000000002"
    """)
    src_dir = joinpath(dir, "src")
    mkpath(src_dir)
    write(joinpath(src_dir, "ScratchPkg.jl"), """
    module ScratchPkg
    greet() = "hello"
    meaning_of_life() = 42
    end
    """)
    test_dir = joinpath(dir, "test")
    mkpath(test_dir)
    return test_dir
end

# ── SubprocessRunner integration ──────────────

@testset "record_item with SubprocessRunner returns ItemCoverage" begin
    mktempdir() do dir
        test_dir = create_scratch_project(dir)
        test_file = joinpath(test_dir, "foo_test.jl")
        write(test_file, """
        @testitem "my_test" begin
            @test 1 == 1
        end
        """)

        ref = Testimonial.TestItemRef(test_file, 1, "my_test")
        runner = Testimonial.SubprocessRunner(timeout=60.0)

        result = Testimonial.record_item(runner, ref)

        @test result isa Testimonial.ItemCoverage
        @test result.item.name == "my_test"
        @test result.item.file == test_file
    end
end

@testset "record_item with SubprocessRunner returns nothing for nonexistent file" begin
    ref = Testimonial.TestItemRef("/nonexistent/path.jl", 1, "test")
    runner = Testimonial.SubprocessRunner(timeout=5.0)

    result = Testimonial.record_item(runner, ref)
    @test result === nothing
end

@testset "record_item with SubprocessRunner returns ItemCoverage for passing test" begin
    mktempdir() do dir
        test_dir = create_scratch_project(dir)
        test_file = joinpath(test_dir, "lines_test.jl")
        write(test_file, """
        @testitem "line_test" begin
            a = 1
            b = 2
            @test a + b == 3
        end
        """)

        ref = Testimonial.TestItemRef(test_file, 1, "line_test")
        runner = Testimonial.SubprocessRunner(timeout=60.0)

        result = Testimonial.record_item(runner, ref)

        @test result isa Testimonial.ItemCoverage
        @test result.item.name == "line_test"
        @test result.item.file == test_file
    end
end

# ── Default record_item(ref) backward compat ──

@testset "record_item(ref) uses SubprocessRunner by default" begin
    mktempdir() do dir
        test_dir = create_scratch_project(dir)
        test_file = joinpath(test_dir, "default_test.jl")
        write(test_file, """
        @testitem "default_test" begin
            @test 1 == 1
        end
        """)

        ref = Testimonial.TestItemRef(test_file, 1, "default_test")
        result = Testimonial.record_item(ref)

        @test result isa Testimonial.ItemCoverage
        @test result.item.name == "default_test"
    end
end