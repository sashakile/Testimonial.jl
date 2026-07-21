# Testimonial.jl — Tests for inter_component_edges in CoverageIndex
#
# Verifies that the CoverageIndex struct has an inter_component_edges
# field and that it's preserved through save/load round-trips.
#
# See testimonial-r24 in openspec/changes/add-component-boundary/

using Testimonial
using Test
using Serialization
using Dates

@testset "CoverageIndex defaults to empty inter_component_edges" begin
    ref = TestItemRef("test/foo.jl", 10, "test_a")
    ic = ItemCoverage(ref, [1, 2], Int[], Dict())
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(ref => ic),
        "abc123", string(VERSION), v"0.1.0", now()
    )
    @test hasfield(typeof(index), :inter_component_edges)
    @test index.inter_component_edges == Dict{String, Set{String}}()
end

@testset "CoverageIndex preserves inter_component_edges" begin
    ref = TestItemRef("test/foo.jl", 10, "test_a")
    ic = ItemCoverage(ref, [1, 2], Int[], Dict())
    edges = Dict{String, Set{String}}(
        "App" => Set(["LibA", "LibB"]),
        "LibA" => Set(["LibB"]),
    )
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(ref => ic),
        "abc123", string(VERSION), v"0.1.0", now(), "", edges
    )
    @test index.inter_component_edges == edges
    @test "App" in keys(index.inter_component_edges)
    @test "LibB" in index.inter_component_edges["App"]
end

@testset "inter_component_edges survives save/load round-trip" begin
    mktempdir() do dir
        cd(dir) do
            ref = TestItemRef("test/foo.jl", 10, "test_a")
            ic = ItemCoverage(ref, [1, 2], Int[], Dict())
            edges = Dict{String, Set{String}}("PkgA" => Set(["PkgB"]))
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123", string(VERSION), v"0.1.0", now(), "", edges
            )
            save_index(index, ".testimonial/index.jls")
            loaded = load_index(".testimonial/index.jls")
            @test loaded.inter_component_edges == edges
        end
    end
end