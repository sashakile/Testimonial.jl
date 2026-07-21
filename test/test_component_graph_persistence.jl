# Testimonial.jl — Tests for storing component graph alongside routing file
#
# Verifies that the component graph is saved/loaded alongside the
# routing file at .testimonial/graph.jls.
#
# See testimonial-22g in openspec/changes/add-component-boundary/

using Testimonial
using Test
using Serialization
using Dates

@testset "save and load component graph" begin
    mktempdir() do dir
        cd(dir) do
            edges = Dict{String, Set{String}}(
                "App" => Set(["LibA", "LibB"]),
                "LibA" => Set(["LibB"]),
            )
            Testimonial.save_component_graph(edges)
            loaded = Testimonial.load_component_graph()

            @test loaded == edges
            @test isfile(".testimonial/graph.jls")
        end
    end
end

@testset "load_component_graph returns empty dict for missing file" begin
    mktempdir() do dir
        cd(dir) do
            loaded = Testimonial.load_component_graph()
            @test loaded == Dict{String, Set{String}}()
        end
    end
end

@testset "load_component_graph handles corrupted file" begin
    mktempdir() do dir
        cd(dir) do
            # Write garbage
            mkpath(".testimonial")
            write(".testimonial/graph.jls", "not valid data")
            loaded = Testimonial.load_component_graph()
            @test loaded == Dict{String, Set{String}}()
        end
    end
end

@testset "component graph saved alongside routing during record_all" begin
    mktempdir() do dir
        cd(dir) do
            # Workspace with two components
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

            write(joinpath(dir, "pkgs/A/src", "alib.jl"), "module ALib end")

            # LibB test covers LibA source (cross-component)
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
            Testimonial.save_component_graph(edges)

            loaded = Testimonial.load_component_graph()
            @test haskey(loaded, "LibB")
            @test "LibA" in loaded["LibB"]
        end
    end
end