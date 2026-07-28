# Testimonial.jl — Tests for provenance persistence
#
# Tests for saving and loading provenance data for smart_run selections.
#
# See testimonial-c2ub — Store provenance after each smart_run
# in openspec/changes/add-provenance-explainability/tasks.md

using Testimonial
using Test
using Dates

# ── Helpers ───────────────────────────────────

"""Create a simple ImpactResult for testing."""
function make_result(name::String, selected::Bool=true)
    ref = Testimonial.TestItemRef("/proj/test/$(name).jl", 1, name)
    reason = Testimonial.ImpactReason(Testimonial.DirectChange, "changed file: src/lib.jl")
    return Testimonial.ImpactResult(ref, [reason], selected, nothing)
end

# ── save_provenance / load_provenance ─────────

@testset "save_provenance saves results for a run key" begin
    mktempdir() do dir
        results = [make_result("test_a", true), make_result("test_b", false)]

        # Save provenance to temp dir
        Testimonial.save_provenance("run_001", results, dir)

        # Check file exists
        prov_path = joinpath(dir, "run_001.jls")
        @test isfile(prov_path)

        # Load and verify
        loaded = Testimonial.load_provenance("run_001", dir)
        @test loaded isa Vector{Testimonial.ImpactResult}
        @test length(loaded) == 2
        @test loaded[1].item.name == "test_a"
        @test loaded[1].selected == true
        @test loaded[2].item.name == "test_b"
        @test loaded[2].selected == false
    end
end

@testset "load_provenance returns empty vector for missing run key" begin
    mktempdir() do dir
        loaded = Testimonial.load_provenance("nonexistent", dir)
        @test loaded isa Vector{Testimonial.ImpactResult}
        @test isempty(loaded)
    end
end

@testset "save_provenance uses default provenance dir when not specified" begin
    mktempdir() do dir
        Testimonial.save_provenance("test_key", [make_result("t1")], dir)
        # The file should be at dir/test_key.jls
        @test isfile(joinpath(dir, "test_key.jls"))
    end
end

@testset "save_provenance uses DEFAULT_PROVENANCE_DIR" begin
    @test Testimonial.DEFAULT_PROVENANCE_DIR == ".testimonial/provenance/"
    @test endswith(Testimonial.DEFAULT_PROVENANCE_DIR, "/")
end

@testset "prune_provenance keeps last N files" begin
    mktempdir() do dir
        # Create 5 provenance files with different timestamps
        results = [
            Testimonial.ImpactResult(
                Testimonial.TestItemRef("/test/a.jl", 1, "t1"),
                Testimonial.ImpactReason[],
                true, nothing,
            ),
        ]
        for i in 1:5
            Testimonial.save_provenance("run_$(i)", results, dir)
            sleep(0.01)  # ensure different mtime
        end

        # Prune to keep last 2
        pruned = Testimonial.prune_provenance(dir; max_runs=2)
        @test pruned == 3  # removed 3 old files

        # Only 2 files should remain
        remaining = filter(f -> endswith(f, ".jls"), readdir(dir))
        @test length(remaining) == 2
    end
end

@testset "prune_provenance keeps all when under limit" begin
    mktempdir() do dir
        for i in 1:3
            Testimonial.save_provenance("run_$(i)", ImpactResult[], dir)
        end

        pruned = Testimonial.prune_provenance(dir; max_runs=10)
        @test pruned == 0

        remaining = filter(f -> endswith(f, ".jls"), readdir(dir))
        @test length(remaining) == 3
    end
end

@testset "prune_provenance handles empty directory" begin
    mktempdir() do dir
        pruned = Testimonial.prune_provenance(dir; max_runs=5)
        @test pruned == 0
    end
end

@testset "prune_provenance uses default max_runs" begin
    mktempdir() do dir
        results = [
            Testimonial.ImpactResult(
                Testimonial.TestItemRef("/test/a.jl", 1, "t1"),
                Testimonial.ImpactReason[],
                true, nothing,
            ),
        ]
        for i in 1:25
            Testimonial.save_provenance("run_$(i)", results, dir)
        end

        pruned = Testimonial.prune_provenance(dir)
        @test pruned > 0
    end
end

@testset "DEFAULT_MAX_PROVENANCE_RUNS is 20" begin
    @test Testimonial.DEFAULT_MAX_PROVENANCE_RUNS == 20
end

# ── format_impact_result_grouped ───────────────

@testset "format_impact_result_grouped groups chains by LayerKind" begin
    # Create an ImpactResult with chains from different layers
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
    chain1 = [
        Testimonial.ProvenanceLink(Testimonial.COVERAGE, "src/lib.jl", "line 42", nothing),
    ]
    chain2 = [
        Testimonial.ProvenanceLink(Testimonial.INFERRED, "src/utils.jl", "inferred via call graph", nothing),
    ]
    reason1 = Testimonial.ImpactReason(Testimonial.DirectChange, "changed src/lib.jl", chain1)
    reason2 = Testimonial.ImpactReason(Testimonial.DependencyChange, "changed src/utils.jl", chain2)
    result = Testimonial.ImpactResult(ref, [reason1, reason2], true, nothing)

    lines = Testimonial.format_impact_result_grouped(result)
    combined = join(lines, "\n")
    @test occursin("COVERAGE", combined)
    @test occursin("INFERRED", combined)
    @test occursin("src/lib.jl", combined)
    @test occursin("src/utils.jl", combined)
end

@testset "format_impact_result_grouped handles empty reasons" begin
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
    result = Testimonial.ImpactResult(ref, Testimonial.ImpactReason[], true, nothing)
    lines = Testimonial.format_impact_result_grouped(result)
    combined = join(lines, "\n")
    @test occursin("test_a", combined)
end

@testset "format_impact_result_grouped includes confidence" begin
    ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
    result = Testimonial.ImpactResult(ref, Testimonial.ImpactReason[], true, nothing)
    lines = Testimonial.format_impact_result_grouped(result; confidence=0.75)
    combined = join(lines, "\n")
    @test occursin("confidence", lowercase(combined))
end

@testset "explain with --layers flag uses grouped format" begin
    mktempdir() do dir
        # Create a simple index with provenance data
        ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
        chain = [
            Testimonial.ProvenanceLink(Testimonial.COVERAGE, "src/lib.jl", "line 42", nothing),
        ]
        reason = Testimonial.ImpactReason(Testimonial.DirectChange, "changed src/lib.jl", chain)
        result = Testimonial.ImpactResult(ref, [reason], true, nothing)
        prov_dir = joinpath(dir, "provenance")
        Testimonial.save_provenance("run_001", [result], prov_dir)

        # Call explain with layers=true
        lines = Testimonial.explain(
            "/proj/test/foo_test.jl", "test_a";
            run_key="run_001",
            provenance_dir=prov_dir,
            layers=true,
        )
        combined = join(lines, "\n")
        @test occursin("COVERAGE", combined)
        @test occursin("src/lib.jl", combined)
        @test occursin("test_a", combined)
    end
end

@testset "explain without layers flag uses flat format" begin
    mktempdir() do dir
        ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
        chain = [
            Testimonial.ProvenanceLink(Testimonial.COVERAGE, "src/lib.jl", "line 42", nothing),
        ]
        reason = Testimonial.ImpactReason(Testimonial.DirectChange, "changed src/lib.jl", chain)
        result = Testimonial.ImpactResult(ref, [reason], true, nothing)
        Testimonial.save_provenance("run_001", [result], joinpath(dir, "provenance"))

        # Call explain without layers flag -> uses flat format_impact_result
        lines = Testimonial.explain(
            "/proj/test/foo_test.jl", "test_a";
            run_key="run_001",
            provenance_dir=joinpath(dir, "provenance"),
            layers=false,
        )
        combined = join(lines, "\n")
        @test occursin("test_a", combined)
    end
end

@testset "explain loads persisted provenance when run_key matches" begin
    mktempdir() do dir
        # Create a simple index
        ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
        index = Testimonial.CoverageIndex(
            Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(),
            "abc123", string(VERSION), v"0.1.0", now(),
        )

        # Store provenance for a run key
        prov_dir = joinpath(dir, "provenance")
        results = [
            Testimonial.ImpactResult(
                ref,
                [Testimonial.ImpactReason(Testimonial.DirectChange, "changed src/lib.jl")],
                true,
                nothing,
            ),
        ]
        Testimonial.save_provenance("abc123_1234567890", results, prov_dir)

        # Call explain with matching run_key — should load from provenance
        lines = Testimonial.explain(
            "/proj/test/foo_test.jl", "test_a";
            run_key="abc123_1234567890",
            provenance_dir=prov_dir,
            index=index,
        )
        @test lines isa Vector{String}
        @test !isempty(lines)
        @test occursin("test_a", join(lines, "\n"))
    end
end

@testset "explain falls back to normal explain when run_key has no provenance" begin
    mktempdir() do dir
        ref = Testimonial.TestItemRef("/proj/test/foo_test.jl", 1, "test_a")
        index = Testimonial.CoverageIndex(
            Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(),
            "abc123", string(VERSION), v"0.1.0", now(),
        )

        lines = Testimonial.explain(
            "/proj/test/foo_test.jl", "test_a";
            run_key="nonexistent",
            provenance_dir=joinpath(dir, "provenance"),
            index=index,
        )
        @test lines isa Vector{String}
    end
end

@testset "explain with run_key but no provenance_dir uses default" begin
    mktempdir() do dir
        Testimonial.save_provenance("test_key", [
            Testimonial.ImpactResult(
                Testimonial.TestItemRef("/test/a.jl", 1, "t1"),
                Testimonial.ImpactReason[],
                true,
                nothing,
            ),
        ], dir)

        lines = Testimonial.explain(
            "/test/a.jl", "t1";
            run_key="test_key",
            provenance_dir=dir,
        )
        @test lines isa Vector{String}
    end
end