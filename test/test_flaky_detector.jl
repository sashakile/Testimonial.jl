# Testimonial.jl — Tests for flaky test detector
#
# Detects tests with inconsistent outcomes across retries
# and quarantines them to prevent false incident creation.

using Testimonial
using Test
using Dates

@testset "record_outcome appends to outcome history" begin
    Testimonial.reset_flaky_history()
    ref = TestItemRef("test/foo.jl", 1, "test_foo")

    Testimonial.record_outcome(ref, true)
    Testimonial.record_outcome(ref, false)
    Testimonial.record_outcome(ref, true)

    history = Testimonial.get_outcome_history(ref)
    @test history == [true, false, true]
end

@testset "is_flaky detects inconsistent outcomes" begin
    Testimonial.reset_flaky_history()
    ref = TestItemRef("test/foo.jl", 1, "test_foo")

    # All passes → not flaky
    for _ in 1:5
        Testimonial.record_outcome(ref, true)
    end
    @test !Testimonial.is_flaky(ref)

    # Mixed outcomes → flaky
    Testimonial.record_outcome(ref, false)
    Testimonial.record_outcome(ref, true)
    @test Testimonial.is_flaky(ref)
end

@testset "is_flaky respects window size" begin
    Testimonial.reset_flaky_history()
    ref = TestItemRef("test/foo.jl", 1, "test_foo")

    # 5 passes, then 3 fails → within window of 5, inconsistent
    # Full history: [true×5, false, false, false]
    for _ in 1:5
        Testimonial.record_outcome(ref, true)
    end
    for _ in 1:3
        Testimonial.record_outcome(ref, false)
    end
    @test Testimonial.is_flaky(ref; window=5)

    # Window of 3: only last 3 are [false, false, false] → consistent (all fail)
    @test !Testimonial.is_flaky(ref; window=3)
end

@testset "is_flaky returns false for no history" begin
    Testimonial.reset_flaky_history()
    ref = TestItemRef("test/unknown.jl", 1, "test_unknown")
    @test !Testimonial.is_flaky(ref)
end

@testset "quarantine and get_quarantined" begin
    Testimonial.reset_flaky_history()
    ref = TestItemRef("test/foo.jl", 1, "test_foo")

    Testimonial.quarantine_test(ref)
    quarantined = Testimonial.get_quarantined_tests()
    @test ("test/foo.jl", "test_foo") in quarantined

    Testimonial.unquarantine_test(ref)
    quarantined = Testimonial.get_quarantined_tests()
    @test !(("test/foo.jl", "test_foo") in quarantined)
end

@testset "compare_selection_vs_outcomes excludes quarantined tests" begin
    Testimonial.reset_flaky_history()
    ref_a = TestItemRef("test/a.jl", 1, "test_a")
    ref_b = TestItemRef("test/b.jl", 1, "test_b")
    ref_c = TestItemRef("test/c.jl", 1, "test_c")

    Testimonial.quarantine_test(ref_b)

    selected = [ref_a]
    all_items = [ref_a, ref_b, ref_c]
    failed_items = [ref_b, ref_c]  # ref_b failed but is quarantined
    changed_content = "src/lib.jl"

    # Pass quarantined tests as exclude set
    quarantined = Testimonial.get_quarantined_tests()
    incidents = Testimonial.compare_selection_vs_outcomes(
        selected, all_items, failed_items, changed_content;
        exclude=quarantined,
    )
    @test length(incidents) == 1  # only ref_c
    @test incidents[1].missed_test == ref_c

    Testimonial.unquarantine_test(ref_b)
end

@testset "reconcile skips flaky test failures" begin
    Testimonial.reset_flaky_history()
    ref_b = TestItemRef("test/b.jl", 1, "test_b")
    Testimonial.quarantine_test(ref_b)

    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")

            selected = [ref_a]
            all_items = [ref_a, ref_b]
            failed_items = [ref_b]  # ref_b failed but is flaky → no incident
            changed_content = "src/lib.jl"

            report = Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            @test report.incidents_detected == 0
        end
    end

    Testimonial.unquarantine_test(ref_b)
end
