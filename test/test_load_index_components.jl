# Testimonial.jl — Tests for load_index with per-component indices
#
# Verifies that load_index correctly reads per-component CoverageIndex
# files when the routing file is present (component boundary mode),
# and still loads flat indices for backward compat.
#
# See testimonial-2jw in openspec/changes/add-component-boundary/

using Testimonial
using Test
using Serialization
using Dates

@testset "load_index loads flat index (backward compat)" begin
    mktempdir() do dir
        cd(dir) do
            ref = TestItemRef("test/foo.jl", 10, "test_a")
            ic = ItemCoverage(ref, [1, 2, 3], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123", string(VERSION), v"0.1.0", now()
            )
            Testimonial.save_index(index, ".testimonial/index.jls")

            loaded = Testimonial.load_index(".testimonial/index.jls")
            @test loaded isa CoverageIndex
            @test length(loaded.items) == 1
            @test loaded.git_hash == "abc123"
        end
    end
end

@testset "load_index loads per-component indices via routing file" begin
    mktempdir() do dir
        cd(dir) do
            # Create per-component indices for PkgA and PkgB
            ref_a1 = TestItemRef("pkgs/PkgA/test/a1.jl", 10, "test_a1")
            ref_a2 = TestItemRef("pkgs/PkgA/test/a2.jl", 5, "test_a2")
            ref_b = TestItemRef("pkgs/PkgB/test/b.jl", 10, "test_b")

            ic_a1 = ItemCoverage(ref_a1, [1, 2], Int[], Dict())
            ic_a2 = ItemCoverage(ref_a2, [3, 4], Int[], Dict())
            ic_b = ItemCoverage(ref_b, [5, 6], Int[], Dict())

            index_a = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a1 => ic_a1, ref_a2 => ic_a2),
                "abc123", string(VERSION), v"0.1.0", now()
            )
            index_b = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_b => ic_b),
                "abc123", string(VERSION), v"0.1.0", now()
            )

            # Save per-component indices and routing file
            Testimonial.save_index(index_a, Testimonial.component_index_path("PkgA"))
            Testimonial.save_index(index_b, Testimonial.component_index_path("PkgB"))
            Testimonial.save_routing(".testimonial", [:PkgA, :PkgB])

            # Load via the routing file (same path as before: .testimonial/index.jls)
            loaded = Testimonial.load_index(".testimonial/index.jls")

            @test loaded isa CoverageIndex
            @test length(loaded.items) == 3

            # All items should be present
            names = sort([ic.item.name for (_, ic) in loaded.items])
            @test names == ["test_a1", "test_a2", "test_b"]
        end
    end
end

@testset "load_index returns nothing for missing routing file" begin
    mktempdir() do dir
        cd(dir) do
            loaded = Testimonial.load_index(".testimonial/index.jls")
            @test loaded === nothing
        end
    end
end

@testset "load_index with missing component dir loads empty index" begin
    mktempdir() do dir
        cd(dir) do
            # Routing file says there's a component, but no component dir exists
            Testimonial.save_routing(".testimonial", [:GhostPkg])

            loaded = Testimonial.load_index(".testimonial/index.jls")

            # Should return an empty index rather than nothing
            @test loaded isa CoverageIndex
            @test isempty(loaded.items)
        end
    end
end

@testset "load_index merges per-component indices correctly" begin
    mktempdir() do dir
        cd(dir) do
            # PkgA has 2 items
            ref_a = TestItemRef("pkgs/PkgA/test/a.jl", 10, "test_a")
            ic_a = ItemCoverage(ref_a, [1, 2], Int[], Dict())
            index_a = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a),
                "abc", string(VERSION), v"0.1.0", now()
            )
            Testimonial.save_index(index_a, Testimonial.component_index_path("PkgA"))

            # PkgB has 1 item but different git hash
            ref_b = TestItemRef("pkgs/PkgB/test/b.jl", 10, "test_b")
            ic_b = ItemCoverage(ref_b, [3, 4], Int[], Dict())
            index_b = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_b => ic_b),
                "xyz", string(VERSION), v"0.1.0", now()
            )
            Testimonial.save_index(index_b, Testimonial.component_index_path("PkgB"))

            Testimonial.save_routing(".testimonial", [:PkgA, :PkgB])

            loaded = Testimonial.load_index(".testimonial/index.jls")
            @test length(loaded.items) == 2
        end
    end
end