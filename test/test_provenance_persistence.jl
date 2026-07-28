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