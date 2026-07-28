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
            @test report.quarantined_excluded == 1
        end
    end

    Testimonial.unquarantine_test(ref_b)
end

@testset "auto_quarantine quarantines flaky tests" begin
    Testimonial.reset_flaky_history()
    ref = TestItemRef("test/foo.jl", 1, "test_foo")

    # Mixed outcomes → flaky
    Testimonial.record_outcome(ref, true)
    Testimonial.record_outcome(ref, false)
    Testimonial.record_outcome(ref, true)

    auto_quarantined = Testimonial.auto_quarantine_flaky()
    @test ("test/foo.jl", "test_foo") in auto_quarantined
    @test ("test/foo.jl", "test_foo") in Testimonial.get_quarantined_tests()

    Testimonial.unquarantine_test(ref)
end

@testset "auto_quarantine skips consistent tests" begin
    Testimonial.reset_flaky_history()
    ref = TestItemRef("test/bar.jl", 1, "test_bar")

    # All passes → not flaky
    for _ in 1:5
        Testimonial.record_outcome(ref, true)
    end

    auto_quarantined = Testimonial.auto_quarantine_flaky()
    @test !(("test/bar.jl", "test_bar") in auto_quarantined)
end

@testset "quarantined test manual edges are excluded from selection" begin
    Testimonial.reset_flaky_history()
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 1 end""")
            run(`git add .`)
            run(`git commit -m "initial"`)

            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            ic_a = ItemCoverage(ref_a, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
                Testimonial.compute_environment_fingerprint(dir),
            )
            save_index(index, ".testimonial/index.jls")

            # Create a manual edge for test_a
            edge = ManualEdge("src/lib.jl", ref_a, now())
            save_manual_edges([edge])

            # Now quarantine test_a
            Testimonial.quarantine_test(ref_a)

            # Modify src/lib.jl to trigger manual edge
            write("src/lib.jl", "module Lib; end")
            run(`git add .`)
            run(`git commit -m "modify src/lib.jl"`)

            # Manual edge provider should exclude quarantined tests
            result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test result isa Vector
            @test isempty(result)  # no tests selected (quarantined edge excluded)

            Testimonial.unquarantine_test(ref_a)
        end
    end
end

@testset "full cycle: record → detect flaky → auto-quarantine → exclude" begin
    Testimonial.reset_flaky_history()
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            # Step 1: Record outcomes — ref_b is flaky
            Testimonial.record_outcome(ref_b, true)
            Testimonial.record_outcome(ref_b, false)
            Testimonial.record_outcome(ref_b, true)

            # Step 2: Auto-quarantine
            quarantined = Testimonial.auto_quarantine_flaky()
            @test ("test/b.jl", "test_b") in quarantined

            # Step 3: Reconcile — ref_b failure should be excluded
            selected = [ref_a]
            all_items = [ref_a, ref_b]
            failed_items = [ref_b]
            changed_content = "src/lib.jl"

            report = Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            @test report.incidents_detected == 0  # ref_b excluded as flaky

            Testimonial.unquarantine_test(ref_b)
        end
    end
end

@testset "clear_quarantine removes flaky flag after consistent passes" begin
    Testimonial.reset_flaky_history()
    ref = TestItemRef("test/foo.jl", 1, "test_foo")

    # Test was flaky, but now has 5 consecutive passes
    Testimonial.quarantine_test(ref)
    for _ in 1:5
        Testimonial.record_outcome(ref, true)
    end

    cleared = Testimonial.clear_quarantine_on_consistent(ref)
    @test cleared
    @test !(("test/foo.jl", "test_foo") in Testimonial.get_quarantined_tests())
end

@testset "clear_quarantine keeps flaky flag on inconsistent" begin
    Testimonial.reset_flaky_history()
    ref = TestItemRef("test/foo.jl", 1, "test_foo")

    Testimonial.quarantine_test(ref)
    Testimonial.record_outcome(ref, true)
    Testimonial.record_outcome(ref, false)  # still inconsistent

    cleared = Testimonial.clear_quarantine_on_consistent(ref)
    @test !cleared
    @test ("test/foo.jl", "test_foo") in Testimonial.get_quarantined_tests()

    Testimonial.unquarantine_test(ref)
end

@testset "record_all skips quarantined tests" begin
    Testimonial.reset_flaky_history()
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            mkpath("src")
            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 1 end""")

            discovered = Testimonial.discover_testitems(["test"])
            @test length(discovered) == 1
            ref_a = discovered[1]

            # Quarantine using the discovered item's ref
            Testimonial.quarantine_test(ref_a)

            # record_all should skip it
            index = Testimonial.record_all(discovered; skip_quarantined=true)
            @test length(index.items) == 0  # test_a was skipped

            Testimonial.unquarantine_test(ref_a)
        end
    end
end

@testset "record_all includes non-quarantined tests" begin
    Testimonial.reset_flaky_history()
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            mkpath("src")
            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 1 end""")

            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")

            # Don't quarantine — test should be recorded
            discovered = Testimonial.discover_testitems(["test"])
            index = Testimonial.record_all(discovered; skip_quarantined=true)
            @test length(index.items) == 1
        end
    end
end

@testset "reconcile reports quarantined_excluded=0 when none excluded" begin
    Testimonial.reset_flaky_history()
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            selected = [ref_a]
            all_items = [ref_a, ref_b]
            failed_items = [ref_b]  # ref_b failed but NOT quarantined
            changed_content = "src/lib.jl"

            report = Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            @test report.quarantined_excluded == 0
            @test report.incidents_detected == 1
        end
    end
end
