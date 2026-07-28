# Testimonial.jl — Tests for ingested run key pruning
#
# Verifies that old run keys are pruned from .testimonial/ingested_runs.jls
# based on a configurable age threshold.
#
# See FEED-004 (idempotent ingestion) and task testimonial-h31

using Testimonial
using Test
using Dates

@testset "prune_ingested_run_keys removes old entries" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            # Add a fresh key (now) and a stale key (10 days ago)
            Testimonial.save_ingested_run_key("recent-run", now())
            Testimonial.save_ingested_run_key("stale-run", now() - Day(10))

            # Prune entries older than 5 days
            pruned = Testimonial.prune_ingested_run_keys(5)
            @test pruned == 1  # one entry was pruned

            remaining = Testimonial.load_ingested_run_keys()
            @test haskey(remaining, "recent-run")
            @test !haskey(remaining, "stale-run")
        end
    end
end

@testset "prune_ingested_run_keys keeps all under threshold" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            Testimonial.save_ingested_run_key("key-a", now() - Day(1))
            Testimonial.save_ingested_run_key("key-b", now() - Hour(6))

            pruned = Testimonial.prune_ingested_run_keys(2)  # 2 days
            @test pruned == 0

            remaining = Testimonial.load_ingested_run_keys()
            @test haskey(remaining, "key-a")
            @test haskey(remaining, "key-b")
        end
    end
end

@testset "prune_ingested_run_keys handles empty store" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            pruned = Testimonial.prune_ingested_run_keys(7)
            @test pruned == 0
        end
    end
end

@testset "prune_ingested_run_keys defaults to 30 days" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            Testimonial.save_ingested_run_key("old-key", now() - Day(60))
            Testimonial.save_ingested_run_key("new-key", now())

            pruned = Testimonial.prune_ingested_run_keys()  # default 30 days
            @test pruned == 1
            @test haskey(Testimonial.load_ingested_run_keys(), "new-key")
        end
    end
end