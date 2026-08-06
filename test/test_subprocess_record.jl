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

# ── Artifact isolation (testimonial-in3s.2) ────

@testset "record_item isolates artifacts per subprocess attempt" begin
    mktempdir() do dir
        test_dir = create_scratch_project(dir)
        test_file = joinpath(test_dir, "isolated_test.jl")
        write(test_file, """
        @testitem "isolated_a" begin
            @test 1 == 1
        end
        """)

        ref = Testimonial.TestItemRef(test_file, 1, "isolated_a")
        runner = Testimonial.SubprocessRunner(timeout=60.0)

        # Run recording — should use per-attempt temp dir
        result = Testimonial.record_item(runner, ref)
        @test result isa Testimonial.ItemCoverage
        @test result.item.name == "isolated_a"

        # Verify no shared tracefile or inference trace was left in pwd
        @test !isfile(joinpath(pwd(), "tracefile.info"))
        @test !isfile(joinpath(pwd(), "inference_trace.jls"))
    end
end

@testset "parallel record_items are isolated and each captures coverage" begin
    mktempdir() do dir
        test_dir = create_scratch_project(dir)

        # Create two test files with disjoint @testitem bodies. On Julia 1.12+
        # the LCOV tracefile does NOT record the test file's own lines
        # (@testitem bodies are macro-expanded/evaled by ReTestItems), so
        # `covered_lines` is empty by design — we instead assert isolation
        # via item identity and verify each recording captured coverage
        # (non-empty `source_files`, which holds the framework/source files
        # the subprocess exercised). Cross-contamination of artifacts would
        # surface as a wrong `item` or a shared tracefile left in pwd.
        test_a = joinpath(test_dir, "test_a.jl")
        write(test_a, """
        @testitem "a_only" begin
            a = 1
            b = 2
            @test a + b == 3
        end
        """)

        test_b = joinpath(test_dir, "test_b.jl")
        write(test_b, """
        @testitem "b_only" begin
            x = 10
            y = 20
            @test x + y == 30
        end
        """)

        ref_a = Testimonial.TestItemRef(test_a, 1, "a_only")
        ref_b = Testimonial.TestItemRef(test_b, 1, "b_only")
        runner = Testimonial.SubprocessRunner(timeout=60.0)

        # Run both recordings in parallel via Threads.@threads
        results = Vector{Union{Testimonial.ItemCoverage, Nothing}}(undef, 2)
        Threads.@threads for i in 1:2
            ref = i == 1 ? ref_a : ref_b
            results[i] = Testimonial.record_item(runner, ref)
        end

        # Both should succeed with their own item identity (attribution isolation)
        @test results[1] isa Testimonial.ItemCoverage
        @test results[2] isa Testimonial.ItemCoverage
        @test results[1].item.name == "a_only"
        @test results[2].item.name == "b_only"
        @test results[1].item.file == test_a
        @test results[2].item.file == test_b

        # Each recording must have captured coverage (non-empty source_files).
        # covered_lines (the test file's own lines) is empty on Julia 1.12+ by
        # design (see comment above), so it is intentionally NOT asserted here.
        @test !isempty(results[1].source_files)
        @test !isempty(results[2].source_files)

        # Verify no shared artifacts were left behind in pwd (isolation of
        # artifact dirs — each record_item gets its own mktempdir()).
        @test !isfile(joinpath(pwd(), "tracefile.info"))
        @test !isfile(joinpath(pwd(), "inference_trace.jls"))
    end
end

# ── Exit code and artifact validation (testimonial-in3s.3) ──

@testset "_recording_succeeded rejects timeout" begin
    @test !Testimonial.CoverageLayer._recording_succeeded(nothing, nothing)
end

@testset "_recording_succeeded rejects nonzero exit" begin
    @test !Testimonial.CoverageLayer._recording_succeeded(1, nothing)
    @test !Testimonial.CoverageLayer._recording_succeeded(2, nothing)
    @test !Testimonial.CoverageLayer._recording_succeeded(3, nothing)
    @test !Testimonial.CoverageLayer._recording_succeeded(-1, nothing)
end

@testset "_recording_succeeded accepts exit 0 without artifact_dir" begin
    @test Testimonial.CoverageLayer._recording_succeeded(0, nothing)
end

@testset "_recording_succeeded rejects missing tracefile in artifact_dir" begin
    mktempdir() do dir
        @test !Testimonial.CoverageLayer._recording_succeeded(0, dir)
    end
end

@testset "_recording_succeeded accepts valid tracefile in artifact_dir" begin
    mktempdir() do dir
        write(joinpath(dir, "tracefile.info"), "SF:/proj/src/lib.jl\nDA:1,1\nend_of_record\n")
        @test Testimonial.CoverageLayer._recording_succeeded(0, dir)
    end
end

@testset "_recording_succeeded rejects empty tracefile in artifact_dir" begin
    mktempdir() do dir
        touch(joinpath(dir, "tracefile.info"))
        @test !Testimonial.CoverageLayer._recording_succeeded(0, dir)
    end
end

@testset "_recording_succeeded rejects garbage-only tracefile in artifact_dir" begin
    mktempdir() do dir
        write(joinpath(dir, "tracefile.info"), "not an lcov file at all\n")
        @test !Testimonial.CoverageLayer._recording_succeeded(0, dir)
    end
end

@testset "_collect_coverage handles missing tracefile without throw" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test.jl")
        write(test_file, "1+1")
        result = Testimonial.CoverageLayer._collect_coverage(
            test_file, Testimonial; artifact_dir=dir,
        )
        @test result == (Int[], Int[], Dict{String, Tuple{Vector{Int}, Vector{Int}}}())
    end
end

@testset "_collect_coverage handles malformed tracefile without throw" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test.jl")
        write(test_file, "1+1")
        write(joinpath(dir, "tracefile.info"), "garbage content")
        result = Testimonial.CoverageLayer._collect_coverage(
            test_file, Testimonial; artifact_dir=dir,
        )
        @test result isa Tuple
    end
end