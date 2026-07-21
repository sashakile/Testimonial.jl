# Testimonial.jl — Tests for bottom-up component resolution in smart_run
#
# Verifies that affected components are correctly resolved from changed
# files and the component graph, including transitive dependencies.
#
# See testimonial-1jn in openspec/changes/add-component-boundary/tasks.md

using Testimonial
using Test
using Dates

# ── _resolve_affected_components ─────────────────

@testset "resolve_affected_components: single component, no dependents" begin
    edges = Dict{String, Set{String}}()
    path_map = Dict{Symbol, String}(
        :LibA => "/proj/pkgs/A",
        :LibB => "/proj/pkgs/B",
    )

    affected = Testimonial.CLI._resolve_affected_components(
        edges,
        ["/proj/pkgs/A/src/widget.jl"],
        path_map,
    )

    @test affected == Set(["LibA"])
end

@testset "resolve_affected_components: single component with direct dependent" begin
    # LibB depends on LibA (B → A)
    edges = Dict{String, Set{String}}(
        "LibB" => Set(["LibA"]),
    )
    path_map = Dict{Symbol, String}(
        :LibA => "/proj/pkgs/A",
        :LibB => "/proj/pkgs/B",
    )

    # Change in LibA should affect LibA and LibB (which depends on LibA)
    affected = Testimonial.CLI._resolve_affected_components(
        edges,
        ["/proj/pkgs/A/src/widget.jl"],
        path_map,
    )

    @test affected == Set(["LibA", "LibB"])
end

@testset "resolve_affected_components: transitive dependencies" begin
    # LibC depends on LibB, LibB depends on LibA
    edges = Dict{String, Set{String}}(
        "LibC" => Set(["LibB"]),
        "LibB" => Set(["LibA"]),
    )
    path_map = Dict{Symbol, String}(
        :LibA => "/proj/pkgs/A",
        :LibB => "/proj/pkgs/B",
        :LibC => "/proj/pkgs/C",
    )

    # Change in LibA should affect LibA, LibB (direct), and LibC (transitive)
    affected = Testimonial.CLI._resolve_affected_components(
        edges,
        ["/proj/pkgs/A/src/widget.jl"],
        path_map,
    )

    @test affected == Set(["LibA", "LibB", "LibC"])
end

@testset "resolve_affected_components: multiple changed components" begin
    # LibB depends on LibA, LibD depends on LibC
    edges = Dict{String, Set{String}}(
        "LibB" => Set(["LibA"]),
        "LibD" => Set(["LibC"]),
    )
    path_map = Dict{Symbol, String}(
        :LibA => "/proj/pkgs/A",
        :LibB => "/proj/pkgs/B",
        :LibC => "/proj/pkgs/C",
        :LibD => "/proj/pkgs/D",
    )

    # Changes in LibA and LibC should affect both chains
    affected = Testimonial.CLI._resolve_affected_components(
        edges,
        [
            "/proj/pkgs/A/src/widget.jl",
            "/proj/pkgs/C/src/gadget.jl",
        ],
        path_map,
    )

    @test affected == Set(["LibA", "LibB", "LibC", "LibD"])
end

@testset "resolve_affected_components: no components changed" begin
    edges = Dict{String, Set{String}}(
        "LibB" => Set(["LibA"]),
    )
    path_map = Dict{Symbol, String}(
        :LibA => "/proj/pkgs/A",
        :LibB => "/proj/pkgs/B",
    )

    # Changed file is not in any known component
    affected = Testimonial.CLI._resolve_affected_components(
        edges,
        ["/proj/vendor/third_party.jl"],
        path_map,
    )

    @test isempty(affected)
end

@testset "resolve_affected_components: empty component graph" begin
    edges = Dict{String, Set{String}}()
    path_map = Dict{Symbol, String}(
        :LibA => "/proj/pkgs/A",
    )

    affected = Testimonial.CLI._resolve_affected_components(
        edges,
        ["/proj/pkgs/A/src/widget.jl"],
        path_map,
    )

    @test affected == Set(["LibA"])
end

@testset "resolve_affected_components: diamond dependency" begin
    # LibB and LibC both depend on LibA, and LibD depends on both LibB and LibC
    edges = Dict{String, Set{String}}(
        "LibB" => Set(["LibA"]),
        "LibC" => Set(["LibA"]),
        "LibD" => Set(["LibB", "LibC"]),
    )
    path_map = Dict{Symbol, String}(
        :LibA => "/proj/pkgs/A",
        :LibB => "/proj/pkgs/B",
        :LibC => "/proj/pkgs/C",
        :LibD => "/proj/pkgs/D",
    )

    # Change in LibA should affect all four
    affected = Testimonial.CLI._resolve_affected_components(
        edges,
        ["/proj/pkgs/A/src/widget.jl"],
        path_map,
    )

    @test affected == Set(["LibA", "LibB", "LibC", "LibD"])
end

