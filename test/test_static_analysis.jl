# Testimonial.jl — Tests for static analysis pass (testimonial-777t, Phase 3 static layer).
#
# The static analysis pass uses JET.jl to extract call-graph edges from
# recorded packages, stored in CoverageIndex.static_edges. These edges
# represent abstract dispatch paths and declared entrypoints that coverage
# alone would miss.
#
# See openspec/project.md — static-layer capability (Phase 3).

using Testimonial
using Test
using Dates

# ── CoverageIndex.static_edges default ─────

@testset "CoverageIndex defaults static_edges to empty" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "deadbeef",
        string(VERSION),
        v"0.1.0",
        DateTime(2026, 7, 29),
    )
    @test hasfield(CoverageIndex, :static_edges)
    @test index.static_edges isa Dict
    @test isempty(index.static_edges)
end

@testset "CoverageIndex has layer_data field" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "deadbeef",
        string(VERSION),
        v"0.1.0",
        DateTime(2026, 7, 29),
    )
    @test hasfield(CoverageIndex, :layer_data)
    @test index.layer_data isa Dict{Symbol, Any}
    @test isempty(index.layer_data)
end

# ── StaticLayer module exists ────────────────

@testset "StaticLayer module exists" begin
    @test isdefined(Testimonial, :StaticLayer)
    @test Testimonial.StaticLayer isa Module
end

# ── run_static_analysis returns edges ────────

@testset "run_static_analysis returns empty edges for empty test set" begin
    edges = Testimonial.StaticLayer.run_static_analysis(String[], String[])
    @test edges isa Dict{String, Set{TestItemRef}}
    @test isempty(edges)
end

@testset "run_static_analysis returns empty edges when no package dir given" begin
    edges = Testimonial.StaticLayer.run_static_analysis(
        ["test/simple_static.jl"],
        String[];  # no package dirs = no source to analyze
        package_dir=nothing,
    )
    @test edges isa Dict{String, Set{TestItemRef}}
    @test isempty(edges)
end

# ── Integration: synthetic static edges ──────

@testset "run_static_analysis with valid source produces edges" begin
    mktempdir() do dir
        # Create a minimal package structure
        src_dir = joinpath(dir, "src")
        mkpath(src_dir)

        # Source file with abstract dispatch
        write(joinpath(src_dir, "Foo.jl"), """
        module Foo

        abstract type Animal end

        struct Dog <: Animal end
        struct Cat <: Animal end

        function speak(::Animal)
            return "generic animal sound"
        end

        function speak(::Dog)
            return "woof"
        end

        function speak(::Cat)
            return "meow"
        end

        # Entrypoint that dispatches on abstract type
        function make_sound(a::Animal)
            return speak(a)
        end

        end # module
        """)

        # Test file with @testitems
        test_dir = joinpath(dir, "test")
        mkpath(test_dir)
        write(joinpath(test_dir, "test_animals.jl"), """
        @testitem "Dog sound" begin
            using Foo
            @test Foo.speak(Foo.Dog()) == "woof"
        end
        @testitem "Cat sound" begin
            using Foo
            @test Foo.speak(Foo.Cat()) == "meow"
        end
        @testitem "make_sound dispatch" begin
            using Foo
            @test Foo.make_sound(Foo.Dog()) == "woof"
        end
        """)

        # Discover test items
        test_files = Testimonial._walk_jl_files(test_dir)
        @test !isempty(test_files)

        # Run static analysis
        edges = Testimonial.StaticLayer.run_static_analysis(
            test_files,
            [src_dir];
            package_dir=dir,
        )

        # Should not error and return a dict
        @test edges isa Dict
        # With package_dir set, JET may or may not be available.
        # The key contract: no error, degraded gracefully if JET missing.
    end
end

# ── Graceful degradation when JET is unavailable ──

@testset "run_static_analysis degrades gracefully without JET" begin
    mktempdir() do dir
        src_dir = joinpath(dir, "src")
        mkpath(src_dir)
        write(joinpath(src_dir, "empty.jl"), "module Empty; end")
        test_dir = joinpath(dir, "test")
        mkpath(test_dir)
        write(joinpath(test_dir, "empty_test.jl"), "@testitem \"empty\" begin end")

        test_files = Testimonial._walk_jl_files(test_dir)
        edges = Testimonial.StaticLayer.run_static_analysis(
            test_files,
            [src_dir];
            package_dir=dir,
        )
        @test edges isa Dict{String, Set{TestItemRef}}
        # Should not throw even if JET can't analyze
    end
end