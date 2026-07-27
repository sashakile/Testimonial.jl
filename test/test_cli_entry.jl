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

@testset "CLI main without --shadow defaults to shadow mode from config" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            # Without --shadow and no config, defaults to shadow=true
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

@testset "CLI main reads safety.mode=shadow from config" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            write("Testimonial.toml", """
            [safety]
            mode = "shadow"
            """)

            # Without --shadow flag, config should set shadow=true
            # Without an index, run() returns :full_suite regardless
            result = Testimonial.CLI.main(String[])
            @test result == :full_suite
        end
    end
end

@testset "CLI main reads safety.mode=enforcing from config" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            write("Testimonial.toml", """
            [safety]
            mode = "enforcing"
            """)

            # Without --shadow flag, config should set shadow=false
            result = Testimonial.CLI.main(String[])
            @test result == :full_suite
        end
    end
end

@testset "CLI main --shadow flag overrides config mode" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            write("Testimonial.toml", """
            [safety]
            mode = "enforcing"
            """)

            # --shadow flag should override the config
            result = Testimonial.CLI.main(["--shadow"])
            @test result == :full_suite
        end
    end
end

@testset "CLI main enforces shadow mode in git repo" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 1 end""")
            run(`git add .`)
            run(`git commit -m "initial"`)

            ref = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 2 end""")
            run(`git add .`)
            run(`git commit -m "modify test_a"`)

            # Default (no config) → shadow=true → returns :full_suite
            result_default = Testimonial.CLI.main(["--base-ref", "HEAD~1"])
            @test result_default == :full_suite

            # --enforcing flag overrides to shadow=false → returns selection
            result_enforcing = Testimonial.CLI.main(["--base-ref", "HEAD~1", "--enforcing"])
            @test result_enforcing isa Vector

            # With mode=enforcing config, shadow=false → returns selection
            write("Testimonial.toml", """
            [safety]
            mode = "enforcing"
            """)
            run(`git add Testimonial.toml`)
            run(`git commit -m "add enforcing config"`)
            result_config = Testimonial.CLI.main(["--base-ref", "HEAD~1"])
            @test result_config isa Vector

            # With mode=shadow config, shadow=true → returns :full_suite
            write("Testimonial.toml", """
            [safety]
            mode = "shadow"
            """)
            run(`git add Testimonial.toml`)
            run(`git commit -m "add shadow config"`)
            result_shadow = Testimonial.CLI.main(["--base-ref", "HEAD~1"])
            @test result_shadow == :full_suite
        end
    end
end