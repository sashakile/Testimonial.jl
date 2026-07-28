# Testimonial.jl — Tests for per-test run history (duration tracking)
#
# Verifies that test durations can be recorded, persisted, and read back
# for use in shard balancing.
#
# See testimonial-2tn in openspec/changes/add-component-boundary/tasks.md

using Testimonial
using Test
using Dates

@testset "run_history empty" begin
    # Empty history = no durations
    history = Testimonial.RunHistory()
    @test isempty(history.entries)
    @test isempty(Testimonial.read_durations(history))
end

@testset "run_history record and read single entry" begin
    ref = TestItemRef("test/foo.jl", 10, "test_foo")
    history = Testimonial.RunHistory()

    Testimonial.record_duration!(history, ref, 1.5)
    @test length(history.entries) == 1

    durations = Testimonial.read_durations(history)
    @test haskey(durations, (ref.file, ref.name))
    @test durations[(ref.file, ref.name)] ≈ 1.5
end

@testset "run_history mean duration over multiple runs" begin
    ref = TestItemRef("test/bar.jl", 5, "test_bar")
    history = Testimonial.RunHistory()

    Testimonial.record_duration!(history, ref, 2.0)
    Testimonial.record_duration!(history, ref, 4.0)
    Testimonial.record_duration!(history, ref, 6.0)

    durations = Testimonial.read_durations(history)
    @test durations[(ref.file, ref.name)] ≈ 4.0  # mean = (2+4+6)/3
end

@testset "run_history multiple test items" begin
    ref_a = TestItemRef("test/a.jl", 10, "test_a")
    ref_b = TestItemRef("test/b.jl", 5, "test_b")
    history = Testimonial.RunHistory()

    Testimonial.record_duration!(history, ref_a, 1.0)
    Testimonial.record_duration!(history, ref_b, 3.5)

    durations = Testimonial.read_durations(history)
    @test length(durations) == 2
    @test durations[(ref_a.file, ref_a.name)] ≈ 1.0
    @test durations[(ref_b.file, ref_b.name)] ≈ 3.5
end

@testset "run_history persistence save and load" begin
    mktempdir() do dir
        ref = TestItemRef("test/baz.jl", 1, "test_baz")
        history = Testimonial.RunHistory()

        Testimonial.record_duration!(history, ref, 2.5)
        save_path = joinpath(dir, "run_history.jls")
        Testimonial.save_run_history(history, save_path)

        # Load into a fresh history
        loaded = Testimonial.load_run_history(save_path)
        @test loaded isa Testimonial.RunHistory
        durations = Testimonial.read_durations(loaded)
        @test haskey(durations, (ref.file, ref.name))
        @test durations[(ref.file, ref.name)] ≈ 2.5
    end
end

@testset "run_history load nonexistent file" begin
    loaded = Testimonial.load_run_history("/nonexistent/path.jls")
    @test loaded isa Testimonial.RunHistory
    @test isempty(loaded.entries)
end

@testset "run_history count and last_duration" begin
    ref = TestItemRef("test/alpha.jl", 15, "test_alpha")
    history = Testimonial.RunHistory()

    Testimonial.record_duration!(history, ref, 1.0)
    Testimonial.record_duration!(history, ref, 3.0)

    entry = history.entries[(ref.file, ref.name)]
    @test entry.count == 2
    @test entry.last_duration ≈ 3.0
    @test entry.mean_duration ≈ 2.0
end

@testset "run_history default path" begin
    # Test that the default save path is .testimonial/run_history.jls
    @test Testimonial.DEFAULT_RUN_HISTORY_PATH == ".testimonial/run_history.jls"
end

@testset "run_history entry persistence save and load" begin
    mktempdir() do dir
        ref = TestItemRef("test/foo.jl", 10, "test_foo")
        history = Testimonial.RunHistory()

        # Add a RunHistoryEntry for this test
        entry = RunHistoryEntry(
            [true, false, true],  # outcomes
            3,                     # attempt_count
            1.0 / 3.0,            # failure_rate
            DateTime(2026, 7, 1),  # first_seen
            DateTime(2026, 7, 27), # last_seen
        )
        Testimonial.record_outcome_history!(history, ref, entry)

        save_path = joinpath(dir, "run_history.jls")
        Testimonial.save_run_history(history, save_path)

        # Load into a fresh history
        loaded = Testimonial.load_run_history(save_path)
        @test loaded isa Testimonial.RunHistory

        # Verify the RunHistoryEntry was persisted
        loaded_entry = Testimonial.get_outcome_history(loaded, ref)
        @test loaded_entry !== nothing
        @test loaded_entry.outcomes == [true, false, true]
        @test loaded_entry.attempt_count == 3
        @test loaded_entry.failure_rate ≈ 1.0 / 3.0
        @test loaded_entry.first_seen == DateTime(2026, 7, 1)
        @test loaded_entry.last_seen == DateTime(2026, 7, 27)
    end
end

@testset "run_history entry missing test returns nothing" begin
    history = Testimonial.RunHistory()
    ref = TestItemRef("test/unknown.jl", 1, "test_unknown")
    @test Testimonial.get_outcome_history(history, ref) === nothing
end

@testset "run_history mixes RunEntry and RunHistoryEntry" begin
    mktempdir() do dir
        ref = TestItemRef("test/bar.jl", 5, "test_bar")
        history = Testimonial.RunHistory()

        # Add duration data (RunEntry) via existing API
        Testimonial.record_duration!(history, ref, 2.5)

        # Add outcome data (RunHistoryEntry) via new API
        entry = RunHistoryEntry(
            [true, false],
            2,
            0.5,
            DateTime(2026, 7, 1),
            DateTime(2026, 7, 27),
        )
        Testimonial.record_outcome_history!(history, ref, entry)

        save_path = joinpath(dir, "run_history.jls")
        Testimonial.save_run_history(history, save_path)

        # Load and verify both types survived
        loaded = Testimonial.load_run_history(save_path)

        # Duration data (RunEntry)
        durations = Testimonial.read_durations(loaded)
        @test haskey(durations, (ref.file, ref.name))
        @test durations[(ref.file, ref.name)] ≈ 2.5

        # Outcome data (RunHistoryEntry)
        loaded_entry = Testimonial.get_outcome_history(loaded, ref)
        @test loaded_entry !== nothing
        @test loaded_entry.outcomes == [true, false]
        @test loaded_entry.attempt_count == 2
        @test loaded_entry.first_seen == DateTime(2026, 7, 1)
    end
end