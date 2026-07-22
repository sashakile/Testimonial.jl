# Testimonial.jl — Tests for shadow mode comparison logic
#
# Tests compare_selection_vs_outcomes() which detects candidate
# missed-selection incidents when a full run reveals test failures
# that the selection would have skipped.
#
# See SAFE-008 in openspec/changes/add-safety-invariants/

using Testimonial
using Test

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