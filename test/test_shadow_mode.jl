# Testimonial.jl — Tests for shadow mode comparison logic
#
# Tests compare_selection_vs_outcomes() which detects candidate
# missed-selection incidents when a full run reveals test failures
# that the selection would have skipped.
#
# See SAFE-008 in openspec/changes/add-safety-invariants/

using Testimonial
using Test
using Dates

@testset "compare_selection_vs_outcomes detects missed candidates" begin
    ref_a = TestItemRef("test/a.jl", 1, "test_a")
    ref_b = TestItemRef("test/b.jl", 1, "test_b")
    ref_c = TestItemRef("test/c.jl", 1, "test_c")
    ref_d = TestItemRef("test/d.jl", 1, "test_d")

    # Selected: a and b only
    selected = [ref_a, ref_b]
    # All items that ran
    all_items = [ref_a, ref_b, ref_c, ref_d]
    # Failed items: c and d (both not selected)
    failed_items = [ref_c, ref_d]
    changed_content = "src/lib.jl"

    incidents = Testimonial.compare_selection_vs_outcomes(selected, all_items, failed_items, changed_content)

    @test incidents isa Vector{MissedSelectionIncident}
    @test length(incidents) == 2
    @test incidents[1].missed_test == ref_c
    @test incidents[1].status == Candidate
    @test incidents[1].changed_content == "src/lib.jl"
    @test incidents[2].missed_test == ref_d
    @test incidents[2].status == Candidate
end

@testset "compare_selection_vs_outcomes no incidents when all selected" begin
    ref_a = TestItemRef("test/a.jl", 1, "test_a")
    ref_b = TestItemRef("test/b.jl", 1, "test_b")

    selected = [ref_a, ref_b]
    all_items = [ref_a, ref_b]
    failed_items = [ref_a]  # a failed but was selected
    changed_content = "src/lib.jl"

    incidents = Testimonial.compare_selection_vs_outcomes(selected, all_items, failed_items, changed_content)
    @test isempty(incidents)
end

@testset "compare_selection_vs_outcomes no incidents when no failures" begin
    ref_a = TestItemRef("test/a.jl", 1, "test_a")
    ref_b = TestItemRef("test/b.jl", 1, "test_b")
    ref_c = TestItemRef("test/c.jl", 1, "test_c")

    selected = [ref_a, ref_b]
    all_items = [ref_a, ref_b, ref_c]
    failed_items = TestItemRef[]  # nothing failed
    changed_content = "src/lib.jl"

    incidents = Testimonial.compare_selection_vs_outcomes(selected, all_items, failed_items, changed_content)
    @test isempty(incidents)
end

@testset "compare_selection_vs_outcomes empty selected set" begin
    ref_a = TestItemRef("test/a.jl", 1, "test_a")

    selected = TestItemRef[]  # nothing selected
    all_items = [ref_a]
    failed_items = [ref_a]  # a failed and wasn't selected
    changed_content = "src/lib.jl"

    incidents = Testimonial.compare_selection_vs_outcomes(selected, all_items, failed_items, changed_content)
    @test length(incidents) == 1
    @test incidents[1].missed_test == ref_a
end

@testset "compare_selection_vs_outcomes empty all_items" begin
    selected = TestItemRef[]
    all_items = TestItemRef[]
    failed_items = TestItemRef[]
    changed_content = "src/lib.jl"

    incidents = Testimonial.compare_selection_vs_outcomes(selected, all_items, failed_items, changed_content)
    @test isempty(incidents)
end

@testset "promote_incidents promotes after threshold" begin
    ref = TestItemRef("test/foo.jl", 1, "test_foo")
    content = "src/lib.jl"

    inc1 = MissedSelectionIncident(content, ref, now(), Candidate)
    inc2 = MissedSelectionIncident(content, ref, now(), Candidate)
    inc3 = MissedSelectionIncident(content, ref, now(), Candidate)

    result = Testimonial.promote_incidents([inc1, inc2, inc3])
    @test length(result) == 3
    @test all(r.status == Promoted for r in result)
end

@testset "promote_incidents does not promote below threshold" begin
    ref = TestItemRef("test/foo.jl", 1, "test_foo")
    content = "src/lib.jl"

    inc1 = MissedSelectionIncident(content, ref, now(), Candidate)
    inc2 = MissedSelectionIncident(content, ref, now(), Candidate)

    result = Testimonial.promote_incidents([inc1, inc2])
    @test length(result) == 2
    @test all(r.status == Candidate for r in result)
end

@testset "promote_incidents returns empty for empty list" begin
    incs = MissedSelectionIncident[]
    result = Testimonial.promote_incidents(incs)
    @test result === incs  # identity return
    @test isempty(result)
end

@testset "promote_incidents handles multiple distinct pairs" begin
    ref_a = TestItemRef("test/a.jl", 1, "test_a")
    ref_b = TestItemRef("test/b.jl", 1, "test_b")
    content = "src/lib.jl"

    incs = [
        MissedSelectionIncident(content, ref_a, now(), Candidate),
        MissedSelectionIncident(content, ref_a, now(), Candidate),
        MissedSelectionIncident(content, ref_a, now(), Candidate),
        MissedSelectionIncident(content, ref_b, now(), Candidate),
    ]

    result = Testimonial.promote_incidents(incs)
    @test length(result) == 4
    promoted = filter(r -> r.status == Promoted, result)
    @test length(promoted) == 3
    @test all(r.missed_test == ref_a for r in promoted)
    candidates = filter(r -> r.status == Candidate, result)
    @test length(candidates) == 1
    @test candidates[1].missed_test == ref_b
end

@testset "promote_incidents respects custom threshold" begin
    ref = TestItemRef("test/foo.jl", 1, "test_foo")
    content = "src/lib.jl"

    inc = MissedSelectionIncident(content, ref, now(), Candidate)
    result = Testimonial.promote_incidents([inc], 1)
    @test length(result) == 1
    @test all(r.status == Promoted for r in result)
end

@testset "promote_incidents with max_age_days filters old incidents" begin
    ref = TestItemRef("test/foo.jl", 1, "test_foo")
    content = "src/lib.jl"
    old_ts = now() - Dates.Day(10)

    incs = [
        MissedSelectionIncident(content, ref, old_ts, Candidate),
        MissedSelectionIncident(content, ref, old_ts, Candidate),
        MissedSelectionIncident(content, ref, now(), Candidate),
        MissedSelectionIncident(content, ref, now(), Candidate),
    ]

    # Default (max_age_days=0): unlimited — counts all 4 → promotes
    result_default = Testimonial.promote_incidents(incs)
    @test all(r.status == Promoted for r in result_default)

    # max_age_days=3: only counts 2 recent (within 3 days) → below threshold
    result_windowed = Testimonial.promote_incidents(incs; max_age_days=3)
    @test all(r.status == Candidate for r in result_windowed)

    # max_age_days=14: all 4 within window → promotes
    result_wide = Testimonial.promote_incidents(incs; max_age_days=14)
    @test all(r.status == Promoted for r in result_wide)
end