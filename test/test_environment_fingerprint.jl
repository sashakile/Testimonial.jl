# Testimonial.jl — Tests for environment change detection
#
# Verifies that environment fingerprints are stored in CoverageIndex,
# computed correctly, and detect changes.
#
# See testimonial-vyu, testimonial-g53 in
# openspec/changes/add-safety-invariants/

using Testimonial
using Test
using Dates

@testset "environment_fingerprint field exists" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
    )

    @test hasfield(CoverageIndex, :environment_fingerprint)
    @test index.environment_fingerprint isa String
end

@testset "environment_fingerprint defaults to empty string" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
    )

    @test index.environment_fingerprint == ""
end

@testset "environment_fingerprint can be set explicitly" begin
    fp = "v1.12.0+abc123"
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
        fp,
    )

    @test index.environment_fingerprint == fp
end

@testset "compute_environment_fingerprint" begin
    fp = Testimonial.compute_environment_fingerprint(".")
    @test fp isa String
    @test !isempty(fp)
end

@testset "environment_fingerprint detects Project.toml changes" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, """
name = "TestPkg"
version = "1.0.0"
[deps]
Foo = "abc123"
""")

        fp1 = Testimonial.compute_environment_fingerprint(dir)

        # Change Project.toml
        write(proj, """
name = "TestPkg"
version = "1.0.0"
[deps]
Foo = "abc123"
Bar = "def456"
""")

        fp2 = Testimonial.compute_environment_fingerprint(dir)

        @test fp1 != fp2
    end
end

@testset "environment_fingerprint includes Julia version" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, "name = \"TestPkg\"\n")

        fp = Testimonial.compute_environment_fingerprint(dir)
        @test occursin(string(VERSION), fp)
    end
end

@testset "environment_fingerprint handles missing Project.toml" begin
    mktempdir() do dir
        # No Project.toml in this dir
        fp = Testimonial.compute_environment_fingerprint(dir)
        @test fp isa String
        @test occursin(string(VERSION), fp)
    end
end

@testset "environment_matches returns true when fingerprints match" begin
    fp = "v1.12.0+abc123"
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
        fp,
    )

    @test Testimonial.environment_matches(index, fp)
end

@testset "environment_matches returns false when fingerprints differ" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
        "v1.11.0+oldhash",
    )

    @test !Testimonial.environment_matches(index, "v1.12.0+newhash")
end

@testset "environment_matches returns false when fingerprint is empty" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
        "",  # empty = not set
    )

    @test !Testimonial.environment_matches(index, "v1.12.0+abc123")
end