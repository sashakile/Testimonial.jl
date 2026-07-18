# Testimonial.jl — Tests for types defined in src/Types.jl

# These tests define the expected shape of our core types.
# They will fail until src/Types.jl is implemented.

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
end

@testset "ImpactResult not selected when no reasons" begin
    ref = TestItemRef("test/bar.jl", 10, "test_bar")
    result = ImpactResult(ref, ImpactReason[])
    @test result.selected == false
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