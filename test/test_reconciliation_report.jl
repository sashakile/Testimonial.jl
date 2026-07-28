# Testimonial.jl — Tests for reconciliation report persistence
#
# Tests that reconcile() persists reports to .testimonial/reconciliation/

using Testimonial
using Test
using Dates
using Serialization

@testset "reconcile persists report to .testimonial/reconciliation/" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            mkpath("test")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            selected = [ref_a]
            all_items = [ref_a, ref_b]
            failed_items = [ref_b]
            changed_content = "src/lib.jl"

            report = Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            @test report isa NamedTuple

            # Verify report file was created
            report_dir = joinpath(".testimonial", "reconciliation")
            @test isdir(report_dir)

            entries = readdir(report_dir)
            @test length(entries) == 1
            @test endswith(entries[1], ".jls")

            # Load and verify the report
            report_path = joinpath(report_dir, entries[1])
            loaded = open(deserialize, report_path, "r")
            @test loaded isa NamedTuple
            @test loaded.incidents_detected == 1
            @test loaded.incidents_promoted == 0
            @test loaded.manual_edges_created == 0
            @test loaded.total_incidents == 1
            @test haskey(loaded, :timestamp)
        end
    end
end

@testset "reconcile creates multiple timestamped reports" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            mkpath("test")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            selected = [ref_a]
            all_items = [ref_a, ref_b]
            failed_items = [ref_b]
            changed_content = "src/lib.jl"

            # Two reconciles should create two separate report files
            Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            Testimonial.reconcile(selected, all_items, failed_items, changed_content)

            report_dir = joinpath(".testimonial", "reconciliation")
            entries = readdir(report_dir)
            @test length(entries) == 2
        end
    end
end

@testset "reconcile report contains timestamp" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            mkpath("test")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            report = Testimonial.reconcile(
                [ref_a], [ref_a, ref_b], [ref_b], "src/lib.jl",
            )

            @test report.timestamp isa DateTime
            # Should be recent
            @test now() - report.timestamp < Dates.Minute(1)
        end
    end
end
