# Testimonial.jl — Tests for seeded fault test seed patterns
#
# Verifies that seed patterns are defined and cover common fault cases.
#
# See testimonial-9hy in openspec/changes/add-safety-invariants/

using Testimonial
using Test

@testset "seeded_fault_patterns defined" begin
    patterns = Testimonial.SEED_FAULT_PATTERNS

    @test length(patterns) >= 3
    @test length(patterns) <= 5
end

@testset "seeded_fault_patterns have required fields" begin
    for (i, pattern) in enumerate(Testimonial.SEED_FAULT_PATTERNS)
        @test haskey(pattern, :name)
        @test haskey(pattern, :description)
        @test haskey(pattern, :action)
        @test haskey(pattern, :revealing_test)
    end
end

@testset "seeded_fault_patterns cover new function" begin
    patterns = Testimonial.SEED_FAULT_PATTERNS
    names = [p.name for p in patterns]
    @test any(n -> occursin("new", lowercase(n)) || occursin("add", lowercase(n)), names)
end

@testset "seeded_fault_patterns cover modified function" begin
    patterns = Testimonial.SEED_FAULT_PATTERNS
    names = [p.name for p in patterns]
    @test any(n -> occursin("modif", lowercase(n)) || occursin("change", lowercase(n)), names)
end

@testset "seeded_fault_patterns cover new file" begin
    patterns = Testimonial.SEED_FAULT_PATTERNS
    names = [p.name for p in patterns]
    @test any(n -> occursin("new-file", lowercase(n)), names)
end

@testset "seeded_fault_patterns cover deleted file" begin
    patterns = Testimonial.SEED_FAULT_PATTERNS
    names = [p.name for p in patterns]
    @test any(n -> occursin("delet", lowercase(n)) || occursin("remov", lowercase(n)), names)
end

@testset "seeded_fault_patterns cover multiple files" begin
    patterns = Testimonial.SEED_FAULT_PATTERNS
    names = [p.name for p in patterns]
    @test any(n -> occursin("multiple", lowercase(n)), names)
end