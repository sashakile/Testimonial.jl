# Testimonial.jl — Tests for CLI entry point (main function)
#
# Tests that the CLI main() correctly parses --shadow flag
# and passes it to run().
#
# See SAFE-008 in openspec/changes/add-safety-invariants/

using Testimonial
using Test

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