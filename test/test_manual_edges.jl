# Testimonial.jl — Tests for manual edge system
#
# Tests ManualEdge struct, persistence, create_manual_edges_from_promoted,
# and the manual_edge_provider query integration.
#
# See SAFE-005 in openspec/changes/add-safety-invariants/

using Testimonial
using Test
using Dates

@testset "ManualEdge struct" begin
    ref = TestItemRef("test/foo.jl", 1, "test_foo")
    ts = now()
    edge = ManualEdge("src/lib.jl", ref, ts)

    @test edge isa ManualEdge
    @test edge.content_path == "src/lib.jl"
    @test edge.test == ref
    @test edge.created_at isa DateTime

    # Equality based on (content_path, test) — timestamp excluded
    edge2 = ManualEdge("src/lib.jl", ref, now())
    @test edge == edge2
    @test hash(edge) == hash(edge2)

    # Different content path → different identity
    edge3 = ManualEdge("src/other.jl", ref, ts)
    @test edge != edge3

    # Different test → different identity
    ref2 = TestItemRef("test/bar.jl", 1, "test_bar")
    edge4 = ManualEdge("src/lib.jl", ref2, ts)
    @test edge != edge4
end

@testset "manual edge persistence: save, load" begin
    mktempdir() do dir
        path = joinpath(dir, ".testimonial", "manual_edges.jls")
        ref = TestItemRef("test/foo.jl", 1, "test_foo")

        # Save edges
        e1 = ManualEdge("src/lib.jl", ref, now())
        e2 = ManualEdge("src/other.jl", ref, now())
        save_manual_edges([e1, e2], path)
        @test isfile(path)

        # Load edges
        loaded = load_manual_edges(path)
        @test loaded isa Vector{ManualEdge}
        @test length(loaded) == 2
        @test loaded[1] == e1
        @test loaded[2] == e2

        # Load from non-existent path returns empty vector
        nope = load_manual_edges(joinpath(dir, "nonexistent.jls"))
        @test nope isa Vector{ManualEdge}
        @test isempty(nope)

        # Load from corrupt file returns empty vector
        bad_path = joinpath(dir, "bad.jls")
        write(bad_path, "not valid serialized data")
        bad_load = load_manual_edges(bad_path)
        @test bad_load isa Vector{ManualEdge}
        @test isempty(bad_load)
    end
end

@testset "manual edge default path constant" begin
    @test MANUAL_EDGES_PATH isa String
    @test endswith(MANUAL_EDGES_PATH, "manual_edges.jls")
end

@testset "create_manual_edges_from_promoted" begin
    mktempdir() do dir
        path = joinpath(dir, ".testimonial", "manual_edges.jls")
        ref = TestItemRef("test/foo.jl", 1, "test_foo")

        # Build incidents: 2 candidates, 1 promoted
        incs = [
            MissedSelectionIncident("src/lib.jl", ref, now(), Candidate),
            MissedSelectionIncident("src/lib.jl", ref, now(), Promoted),
        ]

        edges = create_manual_edges_from_promoted(incs; path=path)
        @test length(edges) == 1
        @test edges[1].content_path == "src/lib.jl"
        @test edges[1].test == ref

        # A second call adds no duplicates
        edges2 = create_manual_edges_from_promoted(incs; path=path)
        @test length(edges2) == 1
    end
end

@testset "create_manual_edges_from_promoted ignores candidates" begin
    mktempdir() do dir
        path = joinpath(dir, ".testimonial", "manual_edges.jls")
        ref = TestItemRef("test/foo.jl", 1, "test_foo")

        incs = [
            MissedSelectionIncident("src/lib.jl", ref, now(), Candidate),
            MissedSelectionIncident("src/other.jl", ref, now(), Candidate),
        ]

        edges = create_manual_edges_from_promoted(incs; path=path)
        @test isempty(edges)
    end
end

@testset "mock: manual_edge_provider returns AlwaysRun for matching content" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            ref = TestItemRef("test/foo.jl", 1, "test_foo")

            # Create a manual edge: "src/lib.jl" changed → force-select test_foo
            edge = ManualEdge("src/lib.jl", ref, now())
            save_manual_edges([edge])

            # The provider doesn't really need the index; pass an empty one
            empty_index = CoverageIndex(Dict{TestItemRef, ItemCoverage}(), "", string(VERSION), v"0.1.0", now())
            changed_files = [abspath("src/lib.jl")]

            results = manual_edge_provider(empty_index, changed_files)
            @test length(results) == 1
            @test results[1].item == ref
            @test results[1].selected == true
            @test results[1].reasons[1].kind == AlwaysRun
        end
    end
end

@testset "mock: manual_edge_provider returns empty for non-matching content" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            ref = TestItemRef("test/foo.jl", 1, "test_foo")
            edge = ManualEdge("src/lib.jl", ref, now())
            save_manual_edges([edge])

            empty_index = CoverageIndex(Dict{TestItemRef, ItemCoverage}(), "", string(VERSION), v"0.1.0", now())
            changed_files = [abspath("src/other.jl")]

            results = manual_edge_provider(empty_index, changed_files)
            @test isempty(results)
        end
    end
end

@testset "mock: manual_edge_provider returns empty when no manual edges exist" begin
    mktempdir() do dir
        cd(dir) do
            empty_index = CoverageIndex(Dict{TestItemRef, ItemCoverage}(), "", string(VERSION), v"0.1.0", now())
            results = manual_edge_provider(empty_index, ["src/lib.jl"])
            @test isempty(results)
        end
    end
end
