# Testimonial.jl — Tests for Persistence.jl (atomic write)

@testset "atomic_write" begin
    mktempdir() do dir
        path = joinpath(dir, "test.json")

        # Basic write
        data = "hello world"
        Testimonial.atomic_write(path, data)
        @test isfile(path)
        @test read(path, String) == data

        # Overwrite
        data2 = "goodbye"
        Testimonial.atomic_write(path, data2)
        @test read(path, String) == data2

        # Nested directory creation
        nested = joinpath(dir, "a", "b", "c", "nested.json")
        Testimonial.atomic_write(nested, "nested")
        @test isfile(nested)
        @test read(nested, String) == "nested"

        # Empty content
        empty_path = joinpath(dir, "empty.json")
        Testimonial.atomic_write(empty_path, "")
        @test read(empty_path, String) == ""

        # No .tmp file left behind
        leftovers = filter(f -> endswith(f, ".tmp"), readdir(dir))
        @test isempty(leftovers)
    end
end

@testset "incident persistence: save, load, append" begin
    mktempdir() do dir
        path = joinpath(dir, ".testimonial", "incidents.jls")

        # Save incidents
        ref = TestItemRef("test/foo.jl", 42, "test_missed")
        inc1 = MissedSelectionIncident("src/lib.jl", ref, now(), Candidate)
        inc2 = MissedSelectionIncident("src/lib.jl", ref, now(), Promoted)

        save_incidents([inc1, inc2], path)
        @test isfile(path)

        # Load incidents
        loaded = load_incidents(path)
        @test loaded isa Vector{MissedSelectionIncident}
        @test length(loaded) == 2
        @test loaded[1] == inc1
        @test loaded[2] == inc2

        # Append a new incident
        inc3 = MissedSelectionIncident("src/other.jl", ref, now(), Dismissed)
        append_incident(inc3, path)

        loaded_again = load_incidents(path)
        @test length(loaded_again) == 3
        @test loaded_again[3] == inc3

        # Load from non-existent path returns empty vector
        nope = load_incidents(joinpath(dir, "nonexistent.jls"))
        @test nope isa Vector{MissedSelectionIncident}
        @test isempty(nope)

        # Load from corrupt file returns empty vector
        bad_path = joinpath(dir, "bad.jls")
        write(bad_path, "not valid serialized data")
        bad_load = load_incidents(bad_path)
        @test bad_load isa Vector{MissedSelectionIncident}
        @test isempty(bad_load)
    end
end

@testset "incident persistence: default path constant" begin
    @test INCIDENTS_PATH isa String
    @test endswith(INCIDENTS_PATH, "incidents.jls")
end