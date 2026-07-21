# Testimonial.jl — Tests for selection cache invalidation
#
# Verifies that selection caches are invalidated when fingerprints
# change, ensuring stale caches are not reused after index rebuilds.
#
# See testimonial-exh in openspec/changes/add-component-boundary/tasks.md

using Testimonial
using Test
using Dates

# ── invalidate_selection_cache ─────────────────

@testset "invalidation: removes cache file for a component" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial/components/MyApp")

            ref = TestItemRef("test/foo.jl", 1, "test_a")
            ic = ImpactResult(ref, [ImpactReason(DirectChange, "test")], true)
            Testimonial.save_selection_cache("MyApp", "fp", [ic])

            cache_path = joinpath(".testimonial", "components", "MyApp", "selection.jls")
            @test isfile(cache_path)

            Testimonial.invalidate_selection_cache("MyApp")
            @test !isfile(cache_path)
            @test Testimonial.load_selection_cache("MyApp") === nothing
        end
    end
end

@testset "invalidation: no-op when no cache file exists" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial/components/MyApp")

            # No cache file to invalidate — should not error
            Testimonial.invalidate_selection_cache("MyApp")
            @test Testimonial.load_selection_cache("MyApp") === nothing
        end
    end
end

@testset "invalidation: invalidate_all clears all caches" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            mkpath(".testimonial/components/MyApp")

            # Create routing file so invalidate_all can discover components
            Testimonial.save_routing(".testimonial", [:MyApp])

            # Create cache file
            ref = TestItemRef("test/foo.jl", 1, "test_a")
            ic = ImpactResult(ref, [ImpactReason(DirectChange, "test")], true)
            Testimonial.save_selection_cache("MyApp", "fp", [ic])

            # Verify cache exists
            @test Testimonial.load_selection_cache("MyApp") !== nothing

            # Invalidate all
            Testimonial.invalidate_all_selection_caches()

            # Verify all caches are gone
            @test Testimonial.load_selection_cache("MyApp") === nothing
        end
    end
end

@testset "invalidation: invalidate_all is no-op with no components" begin
    mktempdir() do dir
        cd(dir) do
            # No routing file — no components to invalidate
            Testimonial.invalidate_all_selection_caches()
            @test true
        end
    end
end

@testset "invalidation: called during record_all with project_dir" begin
    mktempdir() do dir
        cd(dir) do
            write("Project.toml", "name = \"MyApp\"\nversion = \"1.0.0\"\n")
            mkpath("src")
            write("src/app.jl", "module App end")
            mkpath("test")
            write("test/test_app.jl", """@testitem "test_a" begin @test 1==1 end""")

            # Create a stale cache
            path_map = Testimonial.component_paths(dir)
            edges = Dict{String, Set{String}}()
            fp = Testimonial.compute_dependency_fingerprint("MyApp", path_map, edges, dir)
            Testimonial.save_selection_cache("MyApp", "stale_fp", [])

            # Discover test items and record
            items = Testimonial.discover_testitems(["test"])
            runner = Testimonial.SubprocessRunner()
            index = Testimonial.record_all(items, runner; force=true, project_dir=dir)

            # Cache should be invalidated after record_all
            @test Testimonial.load_selection_cache("MyApp") === nothing
        end
    end
end