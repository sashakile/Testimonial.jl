# Testimonial.jl — Tests for building component graph from coverage data
#
# Verifies that inter_component_edges are populated during record_all
# based on which source files each test covers.
#
# See testimonial-440 in openspec/changes/add-component-boundary/

using Testimonial
using Test
using Serialization
using Dates

@testset "build_component_graph with cross-component coverage" begin
    mktempdir() do dir
        cd(dir) do
            # Workspace: PkgA and PkgB
            write(joinpath(dir, "Project.toml"), """
name = "WorkspacePkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/PkgA", "pkgs/PkgB"]
""")

            for (pkg, name) in [("pkgs/PkgA", "PkgA"), ("pkgs/PkgB", "PkgB")]
                pkg_dir = joinpath(dir, pkg)
                mkpath(joinpath(pkg_dir, "test"))
                mkpath(joinpath(pkg_dir, "src"))
                write(joinpath(pkg_dir, "Project.toml"), """
name = "$name"
version = "1.0.0"
""")
            end

            write(joinpath(dir, "pkgs/PkgA/src", "widget.jl"), "module Widget end")
            write(joinpath(dir, "pkgs/PkgB/src", "gadget.jl"), "module Gadget end")

            # PkgA test (covers only PkgA source)
            ref_a = TestItemRef(joinpath(dir, "pkgs/PkgA/test", "a_test.jl"), 1, "test_a")
            source_a = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                joinpath(dir, "pkgs/PkgA/src", "widget.jl") => ([1], Int[]),
            )
            ic_a = ItemCoverage(ref_a, Int[], Int[], source_a)

            # PkgB test (covers PkgA source = cross-component)
            ref_b = TestItemRef(joinpath(dir, "pkgs/PkgB/test", "b_test.jl"), 1, "test_b")
            source_b = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                joinpath(dir, "pkgs/PkgA/src", "widget.jl") => ([1], Int[]),
            )
            ic_b = ItemCoverage(ref_b, Int[], Int[], source_b)

            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a, ref_b => ic_b),
                "abc", string(VERSION), v"0.1.0", now()
            )

            path_map = Testimonial.component_paths(dir)
            edges = Testimonial.build_component_graph!(index, path_map)

            # PkgB depends on PkgA (test_b covers widget.jl in PkgA)
            @test haskey(edges, "PkgB")
            @test "PkgA" in edges["PkgB"]

            # PkgA has no cross-component dependencies (only covers its own source)
            @test !haskey(edges, "PkgA") || isempty(edges["PkgA"])
        end
    end
end

@testset "build_component_graph detects cross-component edges" begin
    mktempdir() do dir
        cd(dir) do
            # Two components
            write(joinpath(dir, "Project.toml"), """
name = "WS"
version = "1.0.0"
[workspace]
packages = ["pkgs/A", "pkgs/B"]
""")

            for (pkg, name) in [("pkgs/A", "LibA"), ("pkgs/B", "LibB")]
                pkg_dir = joinpath(dir, pkg)
                mkpath(joinpath(pkg_dir, "test"))
                mkpath(joinpath(pkg_dir, "src"))
                write(joinpath(pkg_dir, "Project.toml"), "name = \"$name\"\nversion = \"1.0.0\"\n")
            end

            # LibA source
            write(joinpath(dir, "pkgs/A/src", "alib.jl"), "module ALib end")

            # LibB test that covers LibA source (simulated)
            ref_b = TestItemRef(joinpath(dir, "pkgs/B/test", "b_test.jl"), 1, "test_b")
            source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                joinpath(dir, "pkgs/A/src", "alib.jl") => ([1], Int[]),
            )
            ic_b = ItemCoverage(ref_b, Int[], Int[], source_files)
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_b => ic_b),
                "abc", string(VERSION), v"0.1.0", now()
            )

            path_map = Testimonial.component_paths(dir)
            edges = Testimonial.build_component_graph!(index, path_map)

            @test haskey(edges, "LibB")
            @test "LibA" in edges["LibB"]
        end
    end
end

@testset "build_component_graph skips intra-component coverage" begin
    mktempdir() do dir
        cd(dir) do
            write(joinpath(dir, "Project.toml"), "name = \"MyApp\"\nversion = \"1.0.0\"\n")
            mkpath(joinpath(dir, "src"))
            write(joinpath(dir, "src", "app.jl"), "module App end")

            # Test in the same project — no cross-component edges
            ref = TestItemRef("test/foo.jl", 1, "test_foo")
            source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                joinpath(dir, "src", "app.jl") => ([1], Int[]),
            )
            ic = ItemCoverage(ref, Int[], Int[], source_files)
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc", string(VERSION), v"0.1.0", now()
            )

            path_map = Testimonial.component_paths(dir)
            edges = Testimonial.build_component_graph!(index, path_map)

            @test isempty(edges)
        end
    end
end