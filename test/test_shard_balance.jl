# Testimonial.jl — Tests for greedy duration-balancing shard assignment
#
# Tests verify the greedy algorithm: sort tests by descending mean duration,
# assign each to the currently lightest shard.
#
# See testimonial-13f in openspec/changes/add-component-boundary/tasks.md
# See design.md Decision 4

using Testimonial
using Test

@testset "balance_shards empty items" begin
    shards = Testimonial.balance_shards(TestItemRef[], Dict{Tuple{String, String}, Float64}(), 3)
    @test length(shards) == 3
    @test all(isempty, shards)
end

@testset "balance_shards single item" begin
    ref = TestItemRef("test/foo.jl", 10, "test_foo")
    durations = Dict((ref.file, ref.name) => 5.0)

    shards = Testimonial.balance_shards([ref], durations, 2)
    @test length(shards) == 2
    @test length(shards[1]) == 1
    @test shards[1][1] == ref
    @test isempty(shards[2])
end

@testset "balance_shards two items balanced across shards" begin
    a = TestItemRef("test/a.jl", 10, "test_a")
    b = TestItemRef("test/b.jl", 5, "test_b")
    durations = Dict((a.file, a.name) => 5.0, (b.file, b.name) => 3.0)

    shards = Testimonial.balance_shards([a, b], durations, 2)
    @test length(shards) == 2
    # Both shards should have one item each
    @test length(shards[1]) == 1
    @test length(shards[2]) == 1
    # a (5.0) goes first, assigned to shard 1; b (3.0) goes to shard 2
    @test shards[1][1] == a
    @test shards[2][1] == b
end

@testset "balance_shards heavier items first" begin
    # Three items: 10s, 5s, 5s into 2 shards
    heavy = TestItemRef("test/h.jl", 1, "heavy")
    mid   = TestItemRef("test/m.jl", 1, "mid")
    light = TestItemRef("test/l.jl", 1, "light")

    durations = Dict(
        (heavy.file, heavy.name) => 10.0,
        (mid.file, mid.name)   => 5.0,
        (light.file, light.name) => 5.0,
    )

    shards = Testimonial.balance_shards([heavy, mid, light], durations, 2)

    # Greedy: heavy (10) → shard1, mid (5) → shard2 (lighter), light (5) → shard1 (tied shard1=10, shard2=5 → shard2 gets it)
    # Actually: after heavy→s1(10), mid→s2(5)... shard1=10, shard2=5. light(5)→shard2(5+5=10)
    @test length(shards) == 2
    @test length(shards[1]) == 1
    @test length(shards[2]) == 2
    @test shards[1][1] == heavy
end

@testset "balance_shards more shards than items" begin
    a = TestItemRef("test/a.jl", 1, "a")
    durations = Dict((a.file, a.name) => 2.0)

    shards = Testimonial.balance_shards([a], durations, 5)
    @test length(shards) == 5
    @test length(shards[1]) == 1
    @test all(isempty, shards[2:end])
end

@testset "balance_shards many items approximate balance" begin
    # 10 items with durations 1..10 into 3 shards
    refs = [TestItemRef("test/$i.jl", 1, "item_$i") for i in 1:10]
    durations = Dict((r.file, r.name) => Float64(i) for (i, r) in enumerate(refs))

    shards = Testimonial.balance_shards(refs, durations, 3)
    @test length(shards) == 3
    @test sum(length, shards) == 10

    # Compute total duration per shard
    totals = [sum(durations[(r.file, r.name)] for r in shards[i]) for i in 1:3]
    ideal = sum(values(durations)) / 3

    # No shard should deviate more than the max item duration from ideal
    max_item = maximum(values(durations))
    for t in totals
        @test abs(t - ideal) <= max_item
    end
end

@testset "balance_shards no durations falls back to round-robin" begin
    refs = [TestItemRef("test/$i.jl", 1, "item_$i") for i in 1:4]
    durations = Dict{Tuple{String, String}, Float64}()

    shards = Testimonial.balance_shards(refs, durations, 2)
    @test length(shards) == 2
    @test length(shards[1]) == 2
    @test length(shards[2]) == 2
end

@testset "balance_shards zero durations" begin
    refs = [TestItemRef("test/$i.jl", 1, "item_$i") for i in 1:3]
    durations = Dict((r.file, r.name) => 0.0 for r in refs)

    shards = Testimonial.balance_shards(refs, durations, 2)
    @test length(shards) == 2
    # All zero duration → round-robin: s1 gets items 1,3; s2 gets item 2
    @test length(shards[1]) == 2
    @test length(shards[2]) == 1
end

@testset "balance_shards respects n_shards=1" begin
    refs = [TestItemRef("test/$i.jl", 1, "item_$i") for i in 1:5]
    durations = Dict((r.file, r.name) => 1.0 for r in refs)

    shards = Testimonial.balance_shards(refs, durations, 1)
    @test length(shards) == 1
    @test length(shards[1]) == 5
end