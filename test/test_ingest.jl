# Testimonial.jl — Tests for ingest() function
#
# Verifies that post-run coverage ingestion parses sidecars, discovers
# new runtime edges, persists the updated index, and enforces idempotency.
#
# See FEED-001, FEED-002, FEED-004 in
# openspec/changes/add-runtime-feedback/specs/runtime-feedback/spec.md

using Testimonial
using Test
using Dates

@testset "ingest creates runtime edges from new coverage" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            mkpath("test")
            mkpath("src")

            # Create a source file that tests will cover
            write("src/lib.jl", "module Lib\nfunction greet()\n  println(\"hello\")\nend\nend\n")

            # Create a test file with an @testitem
            write("test/test_lib.jl", """
                @testitem "test_greet" begin
                    using Lib: greet
                    greet()
                end
            """)

            # Build an initial coverage index (simulating record_all)
            items = discover_testitems(["test/"])
            ref = first(items)  # test_lib.jl:test_greet

            # Create an index with NO coverage for the test (empty covered_lines)
            initial_cov = ItemCoverage(ref, Int[], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => initial_cov),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            # Simulate a test run: create a coverage sidecar for the source file
            # In real runs, Julia's --code-coverage=user creates .jl.cov files
            write("src/lib.jl.cov", """
                -: 1: module Lib
                -: 2: function greet()
                1: 3:   println("hello")
                -: 4: end
                -: 5: end
            """)

            # Also create a coverage sidecar for the test file itself
            write("test/test_lib.jl.cov", """
                -: 1: @testitem "test_greet" begin
                1: 2:     using Lib: greet
                1: 3:     greet()
                -: 4: end
            """)

            # Call ingest with a unique run key
            report = Testimonial.ingest(; run_key="run-001")

            @test report isa NamedTuple
            @test haskey(report, :runtime_edges_created)
            @test haskey(report, :items_ingested)
            @test haskey(report, :duplicate_skipped)
            @test report.duplicate_skipped == false

            # The test should now have runtime edges to src/lib.jl
            updated = load_index(".testimonial/index.jls")
            @test updated !== nothing
            @test haskey(updated.runtime_edges, ref)
            edges = updated.runtime_edges[ref]
            @test !isempty(edges)
            # Should contain an edge to src/lib.jl
            src_edges = filter(e -> startswith(e[1], "src/lib.jl"), edges)
            @test !isempty(src_edges)
        end
    end
end

@testset "ingest skips duplicate run keys" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            mkpath("test")
            mkpath("src")

            write("src/lib.jl", "module Lib\nend\n")
            write("test/test_lib.jl", """
                @testitem "test_greet" begin end
            """)

            items = discover_testitems(["test/"])
            ref = first(items)
            initial_cov = ItemCoverage(ref, Int[], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => initial_cov),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            # First ingest
            report1 = Testimonial.ingest(; run_key="run-001")
            @test report1.duplicate_skipped == false
            @test report1.runtime_edges_created == 0  # no new coverage

            # Second ingest with same key — should be skipped
            report2 = Testimonial.ingest(; run_key="run-001")
            @test report2.duplicate_skipped == true
            @test report2.runtime_edges_created == 0
        end
    end
end

@testset "ingest requires run_key" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            @test_throws UndefKeywordError Testimonial.ingest()
        end
    end
end

@testset "ingest handles missing index gracefully" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            # No index exists
            report = Testimonial.ingest(; run_key="run-001")
            @test report isa NamedTuple
            @test report.runtime_edges_created == 0
            @test report.items_ingested == 0
        end
    end
end

@testset "ingest records outcome history" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")
            mkpath("test")
            mkpath("src")

            write("src/lib.jl", "module Lib\nend\n")
            write("test/test_lib.jl", """
                @testitem "test_greet" begin end
            """)

            items = discover_testitems(["test/"])
            ref = first(items)
            initial_cov = ItemCoverage(ref, Int[], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => initial_cov),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            # Ingest with pass/fail outcomes
            report = Testimonial.ingest(;
                run_key="run-001",
                passed_items=[ref],
                failed_items=TestItemRef[],
            )

            @test report.items_ingested == 1

            # Verify run history was updated
            history = Testimonial.load_run_history()
            entry = Testimonial.get_outcome_history(history, ref)
            @test entry !== nothing
            @test entry.outcomes == [true]   # passed
            @test entry.attempt_count == 1
            @test entry.failure_rate == 0.0
        end
    end
end