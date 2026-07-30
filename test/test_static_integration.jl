# Testimonial.jl — Integration tests for static layer end-to-end
#
# Exercises the full static pipeline: build a CoverageIndex with static_edges,
# run the query with static_provider, and verify selection.
#
# See openspec/project.md — static-layer capability (Phase 3).
# Ref: testimonial-eudl

using Testimonial
using Test
using Dates

# ── Helpers ───────────────────────────────────

"""Create a scratch monorepo with source and test files for static testing."""
function create_scratch_static_repo(dir::String)
    test_dir = joinpath(dir, "test")
    src_dir = joinpath(dir, "src")
    mkpath(test_dir)
    mkpath(src_dir)

    # Source file with abstract dispatch
    write(joinpath(src_dir, "Shapes.jl"), """
    module Shapes
        abstract type Shape end
        struct Circle <: Shape; radius::Float64; end
        struct Square <: Shape; side::Float64; end

        function area(shape::Shape)
            error("abstract dispatch")
        end

        function area(c::Circle)
            return π * c.radius^2
        end

        function area(s::Square)
            return s.side^2
        end
    end
    """)

    # Test file exercising concrete methods
    write(joinpath(test_dir, "test_shapes.jl"), """
    @testitem "test_circle_area" begin
        @test Shapes.area(Shapes.Circle(1.0)) ≈ π
    end

    @testitem "test_square_area" begin
        @test Shapes.area(Shapes.Square(2.0)) == 4.0
    end
    """)

    # Another source file (no test coverage, for no-static-data test)
    write(joinpath(src_dir, "Utils.jl"), """
    module Utils
        greet() = "hello"
    end
    """)

    return test_dir, src_dir
end

# ── Integration tests ─────────────────────────

@testset "Static layer: abstract dispatch change selects concrete method test" begin
    mktempdir() do dir
        cd(dir) do
            test_dir, src_dir = create_scratch_static_repo(dir)

            # Discover @testitems
            items = Testimonial.discover_testitems([test_dir])
            @test length(items) == 2

            # Find refs by name
            circle_ref = first(i for i in items if i.name == "test_circle_area")
            square_ref = first(i for i in items if i.name == "test_square_area")

            # Build a CoverageIndex with static_edges simulating abstract dispatch
            # When src/Shapes.jl changes (e.g., the area method for Circle), both
            # test_circle_area and test_square_area should be selected via static
            # analysis (they both implement concrete methods of the abstract area function).
            static_edges = Dict{String, Set{Testimonial.TestItemRef}}(
                "src/Shapes.jl" => Set([circle_ref, square_ref]),
            )

            items_dict = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}()
            for ref in items
                items_dict[ref] = Testimonial.ItemCoverage(ref, Int[], Int[], Dict())
            end

            index = Testimonial.CoverageIndex(
                items_dict,
                "abc1234",
                string(VERSION),
                v"0.1.0",
                now(),
                "",
                Dict{String, Set{String}}(),
                Dict{Testimonial.TestItemRef, Vector{Tuple{String, Int}}}(),
                Dict{Testimonial.TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(),
                static_edges,
                Dict{Symbol, Any}(),
                0, 0, 1,
            )

            # Query with static_provider when src/Shapes.jl changes
            providers = [Testimonial.static_provider]
            changed = Dict{String, Set{Int}}(
                "src/Shapes.jl" => Set([10, 15]),
            )

            results = Testimonial.query(providers, index, changed)
            @test length(results) == 2
            names = sort([r.item.name for r in results])
            @test names == ["test_circle_area", "test_square_area"]
            @test all(r -> r.selected == true, results)

            # Verify provenance links are STATIC
            for r in results
                @test any(re -> any(l -> l.layer == Testimonial.STATIC, re.chain), r.reasons)
            end
        end
    end
end

@testset "Static layer: static+coverage overlap deduplicates correctly" begin
    mktempdir() do dir
        cd(dir) do
            test_dir, src_dir = create_scratch_static_repo(dir)

            items = Testimonial.discover_testitems([test_dir])
            circle_ref = first(i for i in items if i.name == "test_circle_area")
            square_ref = first(i for i in items if i.name == "test_square_area")

            # Build a CoverageIndex where:
            # - src/Shapes.jl has static edges to both tests
            # - src/Shapes.jl also has coverage for circle_ref (line-level coverage)
            static_edges = Dict{String, Set{Testimonial.TestItemRef}}(
                "src/Shapes.jl" => Set([circle_ref, square_ref]),
            )

            items_dict = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}()
            for ref in items
                # circle_ref also has line-level coverage of src/Shapes.jl
                if ref.name == "test_circle_area"
                    items_dict[ref] = Testimonial.ItemCoverage(
                        ref, Int[], Int[],
                        Dict("src/Shapes.jl" => ([10, 15, 20], Int[])),
                    )
                else
                    items_dict[ref] = Testimonial.ItemCoverage(ref, Int[], Int[], Dict())
                end
            end

            index = Testimonial.CoverageIndex(
                items_dict,
                "abc1234",
                string(VERSION),
                v"0.1.0",
                now(),
                "",
                Dict{String, Set{String}}(),
                Dict{Testimonial.TestItemRef, Vector{Tuple{String, Int}}}(),
                Dict{Testimonial.TestItemRef, Vector{Tuple{String, String, Int, String, String, Int}}}(),
                static_edges,
                Dict{Symbol, Any}(),
                0, 0, 1,
            )

            # Query with both coverage_provider and static_provider
            changed = Dict{String, Set{Int}}(
                "src/Shapes.jl" => Set([10, 15]),
            )

            providers = [
                Testimonial.coverage_provider(changed),
                Testimonial.static_provider,
            ]

            results = Testimonial.query(providers, index, changed)
            @test length(results) == 2
            names = sort([r.item.name for r in results])
            @test names == ["test_circle_area", "test_square_area"]

            # Both should be selected
            @test all(r -> r.selected == true, results)

            # circle_ref should have reasons from both providers (deduped)
            circle_result = first(r for r in results if r.item.name == "test_circle_area")
            square_result = first(r for r in results if r.item.name == "test_square_area")

            # circle_ref has both coverage and static reasons
            @test length(circle_result.reasons) >= 1

            # square_ref has only static reasons (no coverage)
            @test length(square_result.reasons) >= 1
        end
    end
end

@testset "Static layer: no static data degrades gracefully to coverage" begin
    mktempdir() do dir
        cd(dir) do
            test_dir, src_dir = create_scratch_static_repo(dir)

            items = Testimonial.discover_testitems([test_dir])
            circle_ref = first(i for i in items if i.name == "test_circle_area")

            # Build a CoverageIndex with NO static_edges, but with coverage data
            # for the changed file — simulating the case where static analysis
            # wasn't run but coverage data is available.
            items_dict = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}()
            for ref in items
                items_dict[ref] = Testimonial.ItemCoverage(
                    ref, Int[], Int[],
                    Dict("src/Shapes.jl" => ([10, 15, 20], Int[])),
                )
            end

            index = Testimonial.CoverageIndex(
                items_dict,
                "abc1234",
                string(VERSION),
                v"0.1.0",
                now(),
            )

            # Verify static_edges is empty
            @test isempty(index.static_edges)

            # Query with only coverage_provider — should still select items
            changed = Dict{String, Set{Int}}(
                "src/Shapes.jl" => Set([10, 15]),
            )

            providers = [
                Testimonial.coverage_provider(changed),
            ]

            results = Testimonial.query(providers, index, changed)
            @test !isempty(results)
            @test all(r -> r.selected == true, results)

            # Verify no static links in the results
            for r in results
                for reason in r.reasons
                    for link in reason.chain
                        @test link.layer != Testimonial.STATIC
                    end
                end
            end
        end
    end
end