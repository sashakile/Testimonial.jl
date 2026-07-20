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