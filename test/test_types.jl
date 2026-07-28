# Testimonial.jl — Tests for types defined in src/Types.jl

# These tests define the expected shape of our core types.
# They will fail until src/Types.jl is implemented.

using Dates

@testset "TestItemRef" begin
    ref = TestItemRef("src/foo.jl", 42, "test_bar")

    @test ref isa TestItemRef
    @test ref.file == "src/foo.jl"
    @test ref.line == 42
    @test ref.name == "test_bar"
    @test ref.tags == Symbol[]
    @test ref.file_hash == ""

    # Equality (ignores tags and file_hash)
    ref2 = TestItemRef("src/foo.jl", 42, "test_bar")
    @test ref == ref2
    @test hash(ref) == hash(ref2)

    ref3 = TestItemRef("src/foo.jl", 42, "test_bar", [:integration], "abc123")
    @test ref == ref3  # same identity despite different tags/hash
    @test hash(ref) == hash(ref3)

    # Inequality (different file or name — line is excluded from identity)
    ref4 = TestItemRef("src/bar.jl", 10, "test_bar")
    @test ref != ref4

    ref5 = TestItemRef("src/foo.jl", 10, "other_test")
    @test ref != ref5

    # always_run_reason defaults to nothing
    @test ref.always_run_reason === nothing

    # Can set always_run_reason explicitly
    ref6 = TestItemRef("src/foo.jl", 42, "test_bar", Symbol[], "", LAST_RUN_FAILED)
    @test ref6.always_run_reason == LAST_RUN_FAILED

    # Equality ignores always_run_reason (same identity)
    ref7 = TestItemRef("src/foo.jl", 42, "test_bar", Symbol[], "", NEWLY_ADDED)
    @test ref6 == ref7
    @test hash(ref6) == hash(ref7)

    # component defaults to ""
    @test ref.component == ""

    # Can set component explicitly
    ref8 = TestItemRef("src/foo.jl", 42, "test_bar", Symbol[], "", nothing, "MyPkg")
    @test ref8.component == "MyPkg"

    # Equality ignores component (same identity)
    @test ref == ref8
    @test hash(ref) == hash(ref8)

    # external_inputs defaults to empty
    @test ref.external_inputs == String[]

    # Can set external_inputs explicitly
    ref9 = TestItemRef("src/foo.jl", 42, "test_bar", Symbol[], "", nothing, "", ["config/app.toml", "data/fixtures.csv"])
    @test ref9.external_inputs == ["config/app.toml", "data/fixtures.csv"]

    # Equality ignores external_inputs
    @test ref == ref9
    @test hash(ref) == hash(ref9)
end

@testset "ImpactReasonKind" begin
    @test ImpactReasonKind isa DataType  # @enum creates a type
    @test DirectChange isa ImpactReasonKind
    @test DependencyChange isa ImpactReasonKind
    @test AlwaysRun isa ImpactReasonKind
    @test Unresolved isa ImpactReasonKind

    # Check ordinal values
    @test Int(DirectChange) == 0
    @test Int(DependencyChange) == 1
    @test Int(AlwaysRun) == 2
    @test Int(Unresolved) == 3
end

@testset "AlwaysRunReason" begin
    @test AlwaysRunReason isa DataType
    @test LAST_RUN_FAILED isa AlwaysRunReason
    @test NEWLY_ADDED isa AlwaysRunReason
    @test NO_HISTORY isa AlwaysRunReason
    @test MUST_RUN isa AlwaysRunReason
    @test QUARANTINED isa AlwaysRunReason

    @test Int(LAST_RUN_FAILED) == 0
    @test Int(NEWLY_ADDED) == 1
    @test Int(NO_HISTORY) == 2
    @test Int(MUST_RUN) == 3
    @test Int(QUARANTINED) == 4
end

@testset "ImpactReason" begin
    reason = ImpactReason(DirectChange, "src/foo.jl was modified")
    @test reason.kind == DirectChange
    @test reason.description == "src/foo.jl was modified"
end

@testset "ImpactResult" begin
    ref = TestItemRef("test/bar.jl", 10, "test_bar")
    reasons = [ImpactReason(DirectChange, "direct hit")]
    result = ImpactResult(ref, reasons)
    @test result.item == ref
    @test length(result.reasons) == 1
    @test result.selected == true
    @test result.fallback_reason === nothing
end

@testset "ImpactResult not selected when no reasons" begin
    ref = TestItemRef("test/bar.jl", 10, "test_bar")
    result = ImpactResult(ref, ImpactReason[])
    @test result.selected == false
    @test result.fallback_reason === nothing
end

@testset "ImpactResult with fallback_reason" begin
    ref = TestItemRef("test/bar.jl", 10, "test_bar")
    result = ImpactResult(ref, ImpactReason[], false, "unresolved file: src/lib.jl")
    @test result.fallback_reason == "unresolved file: src/lib.jl"
end

@testset "CoverageGap" begin
    gap = CoverageGap("src/foo.jl", 42, 45)
    @test gap.file == "src/foo.jl"
    @test gap.start_line == 42
    @test gap.end_line == 45
end

@testset "ItemCoverage" begin
    ref = TestItemRef("test/bar.jl", 10, "test_bar")
    cov = ItemCoverage(ref, [1, 2, 3], [4, 5], Dict())
    @test cov.item == ref
    @test cov.covered_lines == [1, 2, 3]
    @test cov.uncovered_lines == [4, 5]
end

@testset "CoverageIndex" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        DateTime(2026, 7, 15),
    )
    @test index isa CoverageIndex
    @test index.git_hash == "abc123"
    @test index.schema_version == v"0.1.0"
end

@testset "MustRunRule" begin
    rule = MustRunRule("src/critical/*.jl", :critical)

    @test rule isa MustRunRule
    @test rule.changed_glob == "src/critical/*.jl"
    @test rule.test_tag == :critical
end

@testset "MustRunRule matches changed file" begin
    rule = MustRunRule("src/critical/*.jl", :critical)

    @test Testimonial.matches_must_run_rule(rule, "src/critical/payment.jl")
    @test Testimonial.matches_must_run_rule(rule, "src/critical/auth.jl")
    @test !Testimonial.matches_must_run_rule(rule, "src/notcritical/foo.jl")
    @test !Testimonial.matches_must_run_rule(rule, "test/critical_test.jl")
end

@testset "MustRunRule matches_must_run with multiple rules" begin
    rules = [
        MustRunRule("src/critical/*.jl", :critical),
        MustRunRule("config/*.toml", :config),
    ]

    changed_files = ["src/critical/payment.jl", "src/notcritical/foo.jl"]
    matched_tags = Testimonial.must_run_tags(rules, changed_files)

    @test :critical in matched_tags
    @test :config ∉ matched_tags
    @test length(matched_tags) == 1
end

@testset "MissedSelectionIncident struct and IncidentStatus enum" begin
    # IncidentStatus values exist
    @test Candidate isa IncidentStatus
    @test Promoted isa IncidentStatus
    @test Dismissed isa IncidentStatus

    # MissedSelectionIncident constructor
    ref = TestItemRef("test/foo.jl", 42, "test_missed")
    incident = MissedSelectionIncident("src/lib.jl", ref, now(), Candidate)

    @test incident isa MissedSelectionIncident
    @test incident.changed_content == "src/lib.jl"
    @test incident.missed_test == ref
    @test incident.timestamp isa DateTime
    @test incident.status == Candidate

    # Equality based on (changed_content, missed_test, status)
    inc2 = MissedSelectionIncident("src/lib.jl", ref, now(), Candidate)
    @test incident == inc2
    @test hash(incident) == hash(inc2)

    # Different status → different identity
    inc3 = MissedSelectionIncident("src/lib.jl", ref, now(), Promoted)
    @test incident != inc3

    # Different content → different identity
    inc4 = MissedSelectionIncident("src/other.jl", ref, now(), Candidate)
    @test incident != inc4
end

@testset "RunHistoryEntry" begin
    ref = TestItemRef("test/foo.jl", 42, "test_foo")
    entry = RunHistoryEntry(
        [true, false, true],  # outcomes: pass, fail, pass
        3,                     # attempt_count
        1.0 / 3.0,            # failure_rate
        DateTime(2026, 7, 1), # first_seen
        DateTime(2026, 7, 27), # last_seen
    )

    @test entry isa RunHistoryEntry
    @test entry.outcomes == [true, false, true]
    @test entry.attempt_count == 3
    @test entry.failure_rate ≈ 1.0 / 3.0
    @test entry.first_seen == DateTime(2026, 7, 1)
    @test entry.last_seen == DateTime(2026, 7, 27)
end