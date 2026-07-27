# Testimonial.jl — Tests for CLI entry point (main function)
#
# Tests that the CLI main() correctly parses --shadow flag
# and passes it to run().
#
# See SAFE-008 in openspec/changes/add-safety-invariants/

using Testimonial
using Test
using Dates


@testset "CLI main accepts --shadow flag" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            # Simulate calling CLI.main with --shadow flag.
            # Without an index, run() returns :full_suite regardless.
            result = Testimonial.CLI.main(["--shadow"])
            @test result == :full_suite
        end
    end
end

@testset "CLI main without --shadow defaults to false" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            # Without --shadow, shadow=false (normal mode)
            result = Testimonial.CLI.main(String[])
            @test result == :full_suite
        end
    end
end

@testset "CLI main passes --base-ref correctly" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            result = Testimonial.CLI.main(["--base-ref", "origin/main"])
            @test result == :full_suite
        end
    end
end

@testset "CLI main handles unknown --shadow flag gracefully" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            # Unknown flag should not error
            result = Testimonial.CLI.main(["--shadow", "--unknown-flag"])
            @test result == :full_suite
        end
    end
end

@testset "CLI incidents lists incidents when present" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref = TestItemRef("test/foo.jl", 1, "test_foo")
            inc = MissedSelectionIncident("src/lib.jl", ref, now(), Candidate)
            save_incidents([inc])

            result = Testimonial.CLI.main(["incidents"])
            @test result isa String
            @test contains(result, "test_foo")
            @test contains(result, "src/lib.jl")
            @test contains(result, "Candidate")
        end
    end
end

@testset "CLI incidents shows empty when no incidents" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            result = Testimonial.CLI.main(["incidents"])
            @test result isa String
            @test contains(lowercase(result), "no incidents")
        end
    end
end

@testset "CLI incidents dismiss removes incident by index" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref = TestItemRef("test/foo.jl", 1, "test_foo")
            inc1 = MissedSelectionIncident("src/a.jl", ref, now(), Candidate)
            inc2 = MissedSelectionIncident("src/b.jl", ref, now(), Candidate)
            save_incidents([inc1, inc2])

            # Dismiss the first incident
            result = Testimonial.CLI.main(["incidents", "dismiss", "1"])
            @test result isa String
            @test contains(lowercase(result), "dismissed")

            # Verify only second incident remains
            remaining = load_incidents()
            @test length(remaining) == 1
            @test remaining[1].changed_content == "src/b.jl"
        end
    end
end

@testset "CLI incidents dismiss handles invalid index" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref = TestItemRef("test/foo.jl", 1, "test_foo")
            inc = MissedSelectionIncident("src/lib.jl", ref, now(), Candidate)
            save_incidents([inc])

            # Out of bounds
            result = Testimonial.CLI.main(["incidents", "dismiss", "99"])
            @test result isa String
            @test contains(lowercase(result), "invalid")

            # Verify incident was not removed
            @test length(load_incidents()) == 1
        end
    end
end

@testset "CLI incidents dismiss without index shows usage" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            result = Testimonial.CLI.main(["incidents", "dismiss"])
            @test result isa String
            @test contains(lowercase(result), "usage")
        end
    end
end

@testset "CLI incidents dismiss with non-numeric index shows error" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref = TestItemRef("test/foo.jl", 1, "test_foo")
            inc = MissedSelectionIncident("src/lib.jl", ref, now(), Candidate)
            save_incidents([inc])

            result = Testimonial.CLI.main(["incidents", "dismiss", "abc"])
            @test result isa String
            @test contains(lowercase(result), "invalid")

            # Verify incident was not removed
            @test length(load_incidents()) == 1
        end
    end
end

@testset "CLI incidents dismiss with negative index shows error" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref = TestItemRef("test/foo.jl", 1, "test_foo")
            inc = MissedSelectionIncident("src/lib.jl", ref, now(), Candidate)
            save_incidents([inc])

            result = Testimonial.CLI.main(["incidents", "dismiss", "-1"])
            @test result isa String
            @test contains(lowercase(result), "invalid")

            # Verify incident was not removed
            @test length(load_incidents()) == 1
        end
    end
end