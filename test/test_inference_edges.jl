# Testimonial.jl — Tests for inference trace parsing and inference_edges
#                    population (testimonial-be7o, Phase 2 inference layer).
#
# The subprocess driver (driver.jl, testimonial-1v4f) serializes the
# caller→callee edges captured by SnoopCompile to an `inference_trace.jls`
# sidecar. Each edge is a 6-tuple:
#   (caller_name, caller_file, caller_line, callee_name, callee_file, callee_line)
#
# These tests verify the parser and the additive merge into
# CoverageIndex.inference_edges from a *known* synthetic trace format,
# without requiring SnoopCompile or a real subprocess run.
#
# See openspec/project.md — inference-layer capability (Phase 2).
# Ref: testimonial-be7o

using Testimonial
using Test
using Serialization
using Dates

# ── Helpers ───────────────────────────────────

"""A representative inference edge 6-tuple type alias."""
const _Edge = Tuple{String, String, Int, String, String, Int}

"""Serialize a known edge vector to a sidecar path, mimicking driver.jl."""
function _write_trace(path::String, edges::Vector{_Edge})
    Serialization.serialize(path, edges)
    return path
end

# ── parse_inference_trace ─────────────────────

@testset "parse_inference_trace round-trips a known sidecar" begin
    mktempdir() do dir
        trace = _write_trace(joinpath(dir, "inference_trace.jls"), [
            ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20),
            ("h", "src/Baz.jl", 5,  "f", "src/Foo.jl", 10),
        ])

        edges = Testimonial.parse_inference_trace(trace)
        @test edges isa Vector
        @test length(edges) == 2
        @test edges[1] == ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20)
        @test edges[2] == ("h", "src/Baz.jl", 5,  "f", "src/Foo.jl", 10)
    end
end

@testset "parse_inference_trace is robust to missing / empty sidecar" begin
    mktempdir() do dir
        # Missing file → empty vector, not an error
        @test Testimonial.parse_inference_trace(joinpath(dir, "nope.jls")) == _Edge[]

        # Empty vector sidecar → empty vector
        empty_trace = _write_trace(joinpath(dir, "empty.jls"), _Edge[])
        @test Testimonial.parse_inference_trace(empty_trace) == _Edge[]
    end
end

# ── inference_content_units ───────────────────
# Each edge's *caller* source location (file, line) is the content unit
# mapped to the test item. The projection is deduped.

@testset "inference_content_units projects caller locations" begin
    edges = [
        ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20),
        ("f", "src/Foo.jl", 10, "h", "src/Baz.jl", 5),   # duplicate caller
        ("k", "src/Qux.jl", 99, "f", "src/Foo.jl", 10),
    ]
    units = Testimonial.inference_content_units(edges)
    @test units isa Vector{Tuple{String, Int}}
    @test Set(units) == Set([("src/Foo.jl", 10), ("src/Qux.jl", 99)])
end

# ── CoverageIndex.inference_edges default ─────

@testset "CoverageIndex defaults inference_edges to empty Dict" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "deadbeef",
        string(VERSION),
        v"0.1.0",
        DateTime(2026, 7, 29),
    )
    @test hasfield(CoverageIndex, :inference_edges)
    @test index.inference_edges isa Dict
    @test isempty(index.inference_edges)
end

# ── merge_inference_edges ─────────────────────

@testset "merge_inference_edges adds edges for a new ref" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "deadbeef", string(VERSION), v"0.1.0", DateTime(2026, 7, 29),
    )
    ref = TestItemRef("test/foo.jl", 1, "foo")
    edges = _Edge[
        ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20),
    ]

    updated = Testimonial.merge_inference_edges(index, ref, edges)
    @test haskey(updated.inference_edges, ref)
    @test updated.inference_edges[ref] == edges
end

@testset "merge_inference_edges is additive and dedups" begin
    ref = TestItemRef("test/foo.jl", 1, "foo")
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "deadbeef", string(VERSION), v"0.1.0", DateTime(2026, 7, 29),
    )
    # Seed an existing inference edge for the ref
    index = Testimonial.merge_inference_edges(index, ref, _Edge[
        ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20),
    ])

    # Merge a new edge plus a duplicate of the existing one
    updated = Testimonial.merge_inference_edges(index, ref, _Edge[
        ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20),  # dup
        ("k", "src/Qux.jl", 99, "f", "src/Foo.jl", 10),  # new
    ])

    @test Set(updated.inference_edges[ref]) == Set(_Edge[
        ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20),
        ("k", "src/Qux.jl", 99, "f", "src/Foo.jl", 10),
    ])
    @test length(updated.inference_edges[ref]) == 2  # deduped
end

@testset "merge_inference_edges preserves runtime_edges and items" begin
    ref = TestItemRef("test/foo.jl", 1, "foo")
    items = Dict{TestItemRef, ItemCoverage}(
        ref => ItemCoverage(ref, [1, 2], Int[], Dict()),
    )
    runtime = Dict{TestItemRef, Vector{Tuple{String, Int}}}(
        ref => [("src/Foo.jl", 10)],
    )
    index = CoverageIndex(
        items, "deadbeef", string(VERSION), v"0.1.0", DateTime(2026, 7, 29),
        "", Dict{String, Set{String}}(), runtime,
    )

    updated = Testimonial.merge_inference_edges(index, ref, _Edge[
        ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20),
    ])

    # runtime_edges untouched (additive, not wiped)
    @test updated.runtime_edges == runtime
    # items untouched
    @test updated.items == items
    # git_hash / fingerprint preserved
    @test updated.git_hash == "deadbeef"
    @test updated.environment_fingerprint == ""
    # inference now populated
    @test haskey(updated.inference_edges, ref)
end

# ── persistence round-trip ────────────────────

@testset "save_index / load_index preserves inference_edges" begin
    mktempdir() do dir
        ref = TestItemRef("test/foo.jl", 1, "foo")
        index = CoverageIndex(
            Dict{TestItemRef, ItemCoverage}(),
            "deadbeef", string(VERSION), v"0.1.0", DateTime(2026, 7, 29),
        )
        index = Testimonial.merge_inference_edges(index, ref, _Edge[
            ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20),
        ])

        path = joinpath(dir, "index.jls")
        Testimonial.save_index(index, path)
        loaded = Testimonial.load_index(path)

        @test loaded !== nothing
        @test haskey(loaded.inference_edges, ref)
        @test loaded.inference_edges[ref] == _Edge[
            ("f", "src/Foo.jl", 10, "g", "src/Bar.jl", 20),
        ]
    end
end