# Testimonial.jl — Tests for always-run set eviction logic
#
# Verifies that tests are evicted from the always-run set after
# N consecutive passing runs, and re-added on failure.
#
# See testimonial-on7 in openspec/changes/add-safety-invariants/

using Testimonial
using Test

@testset "always_run_eviction" begin
    ref = TestItemRef("test/foo.jl", 10, "test_foo")

    # Initially: no history, 0 consecutive passes
    @test Testimonial.consecutive_passes(ref) == 0
    @test !Testimonial.should_evict(ref)

    # After 1 pass: still below threshold (default 5)
    Testimonial.record_run(ref, true)
    @test Testimonial.consecutive_passes(ref) == 1
    @test !Testimonial.should_evict(ref)

    # After 5 passes: evicted
    for _ in 1:4
        Testimonial.record_run(ref, true)
    end
    @test Testimonial.consecutive_passes(ref) == 5
    @test Testimonial.should_evict(ref)

    # After a failure: counter resets to 0
    Testimonial.record_run(ref, false)
    @test Testimonial.consecutive_passes(ref) == 0
    @test !Testimonial.should_evict(ref)
end

@testset "always_run_eviction separate refs are independent" begin
    ref_a = TestItemRef("test/a.jl", 10, "test_a")
    ref_b = TestItemRef("test/b.jl", 5, "test_b")

    Testimonial.record_run(ref_a, true)
    Testimonial.record_run(ref_b, false)

    @test Testimonial.consecutive_passes(ref_a) == 1
    @test Testimonial.consecutive_passes(ref_b) == 0
end

@testset "always_run_eviction default threshold" begin
    @test Testimonial.DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD == 5
end

@testset "always_run_eviction configurable threshold" begin
    ref = TestItemRef("test/bar.jl", 1, "test_bar")
    Testimonial.record_run(ref, true; threshold=2)

    @test Testimonial.consecutive_passes(ref) == 1
    @test !Testimonial.should_evict(ref; threshold=2)

    Testimonial.record_run(ref, true; threshold=2)
    @test Testimonial.should_evict(ref; threshold=2)
end

@testset "always_run_eviction reset_always_run_state" begin
    ref = TestItemRef("test/baz.jl", 1, "test_baz")

    for _ in 1:3
        Testimonial.record_run(ref, true)
    end
    @test Testimonial.consecutive_passes(ref) == 3

    Testimonial.reset_always_run_state(ref)
    @test Testimonial.consecutive_passes(ref) == 0
end

@testset "get_always_run_tests returns tests below eviction threshold" begin
    # Reset state
    ref_a = TestItemRef("test/a.jl", 1, "test_a")
    ref_b = TestItemRef("test/b.jl", 1, "test_b")
    Testimonial.reset_always_run_state(ref_a)
    Testimonial.reset_always_run_state(ref_b)

    # ref_a: 2 consecutive passes → not yet evictable (below threshold 5)
    Testimonial.record_run(ref_a, true)
    Testimonial.record_run(ref_a, true)
    @test Testimonial.consecutive_passes(ref_a) == 2
    @test !Testimonial.should_evict(ref_a)

    # ref_b: 0 consecutive passes (failed last run) → always-run
    Testimonial.record_run(ref_b, false)
    @test Testimonial.consecutive_passes(ref_b) == 0
    @test !Testimonial.should_evict(ref_b)

    # get_always_run_tests should return both
    always_run = Testimonial.get_always_run_tests()
    @test always_run isa Vector{Tuple{String, String}}
    @test ("test/a.jl", "test_a") in always_run
    @test ("test/b.jl", "test_b") in always_run
end

@testset "get_always_run_tests excludes evicted tests" begin
    ref = TestItemRef("test/evicted.jl", 1, "test_evicted")
    Testimonial.reset_always_run_state(ref)

    for _ in 1:5
        Testimonial.record_run(ref, true)
    end
    @test Testimonial.should_evict(ref)

    always_run = Testimonial.get_always_run_tests()
    @test !(("test/evicted.jl", "test_evicted") in always_run)
end

@testset "run merges always-run tests into selection" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            # Two test files: test_a will be selected, test_b won't be
            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 1 end""")
            write("test/test_b.jl", """@testitem "test_b" begin @test 1 == 1 end""")
            run(`git add .`)
            run(`git commit -m "initial"`)

            # Build index with both items
            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            ref_b = TestItemRef(abspath("test/test_b.jl"), 1, "test_b", Symbol[], "def")
            ic_a = ItemCoverage(ref_a, [1], Int[], Dict())
            ic_b = ItemCoverage(ref_b, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a, ref_b => ic_b),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            # Mark test_b as always-run (set it to 0 consecutive passes)
            # by recording a failure
            Testimonial.record_run(ref_b, false)
            Testimonial.record_run(ref_a, true)

            # Modify test_a to trigger selection
            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 2 end""")
            run(`git add .`)
            run(`git commit -m "modify test_a"`)

            # run() should include both test_a (selected) and test_b (always-run)
            result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test result isa Vector
            @test !isempty(result)
            result_names = Set(r.item.name for r in result)
            @test "test_a" in result_names
            @test "test_b" in result_names
        end
    end
end