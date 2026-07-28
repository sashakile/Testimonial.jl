# Testimonial.jl — Tests for reconcile() function
#
# Tests the post-run reconciliation pipeline that detects
# missed-selection incidents, promotes them, and creates manual edges.

using Testimonial
using Test
using Dates
using Serialization

@testset "reconcile detects missed incidents and creates manual edges" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            selected = [ref_a]
            all_items = [ref_a, ref_b]
            failed_items = [ref_b]  # test_b failed, wasn't selected
            changed_content = "src/lib.jl"

            # First reconcile: 1 incident, below threshold
            report1 = Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            @test report1 isa NamedTuple
            @test report1.incidents_detected == 1
            @test report1.incidents_promoted == 0
            @test report1.manual_edges_created == 0
            @test report1.total_incidents == 1

            # Two more reconciles with same key → reaches threshold
            for _ in 1:2
                Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            end

            # Now verify directly
            incidents = load_incidents()
            @test length(incidents) == 3
            promoted_count = count(i -> i.status == Promoted, incidents)
            @test promoted_count == 3

            edges = load_manual_edges()
            @test length(edges) == 1
            @test edges[1].content_path == "src/lib.jl"
            @test edges[1].test == ref_b
        end
    end
end

@testset "reconcile handles no failed items" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            selected = [ref_a, ref_b]
            all_items = [ref_a, ref_b]
            failed_items = TestItemRef[]  # nothing failed
            changed_content = "src/lib.jl"

            report = Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            @test report.incidents_detected == 0
            @test report.incidents_promoted == 0
            @test report.manual_edges_created == 0
        end
    end
end

@testset "reconcile handles empty selection" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")

            selected = TestItemRef[]  # nothing selected
            all_items = [ref_a]
            failed_items = [ref_a]  # a failed but nothing was selected
            changed_content = "src/lib.jl"

            report = Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            @test report.incidents_detected == 1
            @test report.total_incidents == 1
        end
    end
end

@testset "reconcile respects custom threshold" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            selected = [ref_a]
            all_items = [ref_a, ref_b]
            failed_items = [ref_b]
            changed_content = "src/lib.jl"

            # Custom threshold=1 — promotes immediately
            report = Testimonial.reconcile(
                selected, all_items, failed_items, changed_content;
                promote_threshold=1,
            )
            @test report.incidents_detected == 1
            @test report.incidents_promoted == 1
            @test report.manual_edges_created == 1
        end
    end
end

@testset "reconcile: selected failures are not incidents" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            selected = [ref_a, ref_b]
            all_items = [ref_a, ref_b]
            failed_items = [ref_a]  # test_a failed but WAS selected → no incident
            changed_content = "src/lib.jl"

            report = Testimonial.reconcile(selected, all_items, failed_items, changed_content)
            @test report.incidents_detected == 0
            @test report.total_incidents == 0
        end
    end
end

@testset "reconcile: multiple content paths are independent" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref = TestItemRef("test/foo.jl", 1, "test_foo")

            selected = TestItemRef[]
            all_items = [ref]
            failed_items = [ref]

            # Reconcile for two different content paths
            r1 = Testimonial.reconcile(selected, all_items, failed_items, "src/a.jl")
            r2 = Testimonial.reconcile(selected, all_items, failed_items, "src/b.jl")

            @test r1.incidents_detected == 1
            @test r2.incidents_detected == 1
            @test r1.total_incidents == 1
            @test r2.total_incidents == 2  # separate incidents per content path

            # Promote — still below threshold for both
            incidents = load_incidents()
            @test length(incidents) == 2
            @test all(i.status == Candidate for i in incidents)
        end
    end
end

@testset "reconcile report is persisted to disk" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            ref_a = TestItemRef("test/a.jl", 1, "test_a")
            ref_b = TestItemRef("test/b.jl", 1, "test_b")

            report = Testimonial.reconcile(
                [ref_a], [ref_a, ref_b], [ref_b], "src/lib.jl",
            )

            # Verify persisted report matches returned report
            report_dir = joinpath(".testimonial", "reconciliation")
            @test isdir(report_dir)
            entries = readdir(report_dir)
            @test length(entries) == 1

            loaded = open(deserialize, joinpath(report_dir, entries[1]), "r")
            @test loaded.incidents_detected == report.incidents_detected
            @test loaded.incidents_promoted == report.incidents_promoted
            @test loaded.manual_edges_created == report.manual_edges_created
            @test loaded.total_incidents == report.total_incidents
            @test loaded.total_manual_edges == report.total_manual_edges
            @test loaded.timestamp isa DateTime
        end
    end
end
