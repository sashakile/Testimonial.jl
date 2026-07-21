# Testimonial.jl — Tests for per-component selection cache
#
# Verifies that selection results are cached per component keyed on
# dependency fingerprint, and that cached results are reused when
# the fingerprint is unchanged.
#
# See testimonial-cff in openspec/changes/add-component-boundary/tasks.md

using Testimonial
using Test
using Dates

# ── save_selection_cache / load_selection_cache ──

@testset "selection cache: save and load round-trip" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial/components/MyApp")

            ref = TestItemRef("test/foo.jl", 1, "test_a")
            ic = ImpactResult(ref, [ImpactReason(DirectChange, "test")], true)
            results = [ic]

            Testimonial.save_selection_cache("MyApp", "abc123", results)
            loaded = Testimonial.load_selection_cache("MyApp")

            @test loaded !== nothing
            @test loaded[1] == "abc123"
            @test length(loaded[2]) == 1
            @test loaded[2][1].item.name == "test_a"
            @test loaded[2][1].selected == true
        end
    end
end

@testset "selection cache: returns nothing when no cache exists" begin
    mktempdir() do dir
        cd(dir) do
            result = Testimonial.load_selection_cache("NonExistent")
            @test result === nothing
        end
    end
end

@testset "selection cache: returns nothing on corrupted cache" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial/components/MyApp")
            write(".testimonial/components/MyApp/selection.jls", "not valid serialized data")

            result = Testimonial.load_selection_cache("MyApp")
            @test result === nothing
        end
    end
end

@testset "selection cache: overwrites existing cache" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial/components/MyApp")

            ref1 = TestItemRef("test/foo.jl", 1, "test_a")
            ic1 = ImpactResult(ref1, [ImpactReason(DirectChange, "test")], true)
            Testimonial.save_selection_cache("MyApp", "fp1", [ic1])

            ref2 = TestItemRef("test/bar.jl", 1, "test_b")
            ic2 = ImpactResult(ref2, [ImpactReason(DirectChange, "test")], true)
            Testimonial.save_selection_cache("MyApp", "fp2", [ic2])

            loaded = Testimonial.load_selection_cache("MyApp")
            @test loaded[1] == "fp2"
            @test loaded[2][1].item.name == "test_b"
        end
    end
end

# ── Cache integration in _run_component_aware ──

@testset "selection cache: reused when fingerprint matches" begin
    mktempdir() do dir
        cd(dir) do
            write("Project.toml", "name = \"MyApp\"\nversion = \"1.0.0\"\n")
            mkpath("src")
            write("src/app.jl", "module App end")
            mkpath("test")
            test_file = abspath("test/test_app.jl")
            write(test_file, """@testitem "test_a" begin @test 1==1 end""")

            # Build a minimal index — item has component set so scoped query works
            ref = TestItemRef(test_file, 1, "test_a", Symbol[], "", nothing, "MyApp")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc", string(VERSION), v"0.1.0", now(), "",
                Dict{String, Set{String}}(),
            )

            path_map = Testimonial.component_paths(dir)
            edges = Dict{String, Set{String}}()
            changed = Dict{String, Set{Int}}(
                test_file => Set([1]),
            )
            abs_test_dirs = [abspath("test")]
            changed_files = [test_file]

            # Pre-populate cache with a known fingerprint
            fp = Testimonial.compute_dependency_fingerprint("MyApp", path_map, edges, dir)
            cached_results = [ImpactResult(ref, [ImpactReason(DirectChange, "cached")], true)]
            Testimonial.save_selection_cache("MyApp", fp, cached_results)

            # Run component-aware — should use cache
            results = Testimonial.CLI._run_component_aware(
                index, changed, changed_files, abs_test_dirs, path_map, edges, dir,
            )

            @test length(results) == 1
            @test results[1].item.name == "test_a"
            # Verify the reason confirms it came from cache
            @test results[1].reasons[1].description == "cached"
        end
    end
end

@testset "selection cache: fresh query when fingerprint differs" begin
    mktempdir() do dir
        cd(dir) do
            write("Project.toml", "name = \"MyApp\"\nversion = \"1.0.0\"\n")
            mkpath("src")
            write("src/app.jl", "module App end")
            mkpath("test")
            test_file = abspath("test/test_app.jl")
            write(test_file, """@testitem "test_a" begin @test 1==1 end""")

            ref = TestItemRef(test_file, 1, "test_a", Symbol[], "", nothing, "MyApp")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc", string(VERSION), v"0.1.0", now(), "",
                Dict{String, Set{String}}(),
            )

            path_map = Testimonial.component_paths(dir)
            edges = Dict{String, Set{String}}()
            changed = Dict{String, Set{Int}}(
                test_file => Set([1]),
            )
            abs_test_dirs = [abspath("test")]
            changed_files = [test_file]

            # Pre-populate cache with a DIFFERENT fingerprint
            Testimonial.save_selection_cache("MyApp", "stale_fingerprint", [])

            # Run component-aware — should NOT use stale cache, should query fresh
            results = Testimonial.CLI._run_component_aware(
                index, changed, changed_files, abs_test_dirs, path_map, edges, dir,
            )

            # Should find the test item via fresh query
            @test length(results) == 1
            @test results[1].item.name == "test_a"
            # Reason should be from the fresh query, not the cached "stale"
            @test results[1].reasons[1].kind == DirectChange
        end
    end
end