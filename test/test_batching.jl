# Testimonial.jl — Tests for file-grouped batching of subprocess recording
#
# Batching collapses one subprocess per @testitem into one subprocess per
# test FILE, trading per-item coverage granularity for startup-cost
# amortisation. Opt-in via `record_all(...; batch_by_file=true)`.
#
# See ticket testimonial-ru5t (Optimize subprocess overhead with batching).

using Testimonial
using Test

# ── Test-only runner that records batch invocations ─────────
# Defined at module scope so methods can attach cleanly.

struct SoloRunner <: Testimonial.AbstractRunner end

function Testimonial.record_item(runner::SoloRunner, ref::Testimonial.TestItemRef)
    return Testimonial.ItemCoverage(ref, Int[], Int[], Dict())
end

# ── Helpers ───────────────────────────────────

function create_two_file_project(dir::String)
    test_dir = joinpath(dir, "test")
    mkpath(test_dir)
    write(joinpath(test_dir, "foo_test.jl"), """
    @testitem "test_a" begin
        @test 1 == 1
    end
    """)
    write(joinpath(test_dir, "bar_test.jl"), """
    @testitem "test_b" begin
        @test 2 == 2
    end

    @testitem "test_c" begin
        @test 3 == 3
    end
    """)
    return test_dir
end

# ── record_all with batch_by_file ─────────────

@testset "record_all batch_by_file groups items by file (one subprocess per file)" begin
    mktempdir() do dir
        test_dir = create_two_file_project(dir)
        runner = MockRunner()
        items = Testimonial.discover_testitems([test_dir])

        index = record_all(items, runner; force=true, batch_by_file=true)

        @test length(index.items) == 3

        # 2 files → exactly 2 batched subprocess invocations (not 3 per-item)
        @test length(runner.batches) == 2

        # Every item name appears exactly once across the batches
        all_names = sort(vcat(runner.batches...))
        @test all_names == ["test_a", "test_b", "test_c"]
    end
end

@testset "record_all without batch_by_file uses per-item recording" begin
    mktempdir() do dir
        test_dir = create_two_file_project(dir)
        runner = MockRunner()
        items = Testimonial.discover_testitems([test_dir])

        record_all(items, runner; force=true)

        # Default path: no batched invocations recorded
        @test isempty(runner.batches)
        # Per-item path populates TESTIMONIAL_ITEM
        @test haskey(runner.captured_env, "TESTIMONIAL_ITEM")
    end
end

@testset "record_batch default falls back to per-item record_item" begin
    # SoloRunner defines record_item but NOT record_batch, so the
    # AbstractRunner default must loop record_item per ref.
    refs = [
        Testimonial.TestItemRef("/tmp/x.jl", 1, "a"),
        Testimonial.TestItemRef("/tmp/x.jl", 2, "b"),
    ]
    results = Testimonial.record_batch(SoloRunner(), refs)
    @test length(results) == 2
    @test all(r !== nothing for r in results)
    @test [r.item.name for r in results] == ["a", "b"]
end

@testset "build_driver_command accepts a list of item names" begin
    cmd, env = Testimonial.build_driver_command(
        "/proj/test/foo_test.jl",
        ["test_a", "test_b"];
        runner_dir="scripts/TestimonialRunner",
    )
    @test haskey(env, "TESTIMONIAL_ITEMS")
    @test split(env["TESTIMONIAL_ITEMS"], "\n") == ["test_a", "test_b"]
    # Single-item env var is not set in the batch form
    @test !haskey(env, "TESTIMONIAL_ITEM")
end
