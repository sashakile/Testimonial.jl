# Testimonial.jl — End-to-end incident lifecycle tests
#
# Tests the full incident lifecycle:
# detect → save → load → promote → create manual edge → force selection
#
# See SAFE-005 in openspec/changes/add-safety-invariants/

using Testimonial
using Test
using Dates

@testset "full lifecycle: detect → promote → manual edge → selection" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 1 end""")
            write("test/test_b.jl", """@testitem "test_b" begin @test 1 == 1 end""")
            write("src/lib.jl", "# placeholder\n")
            run(`git add .`)
            run(`git commit -m "initial"`)

            # Build index with both items
            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            ref_b = TestItemRef(abspath("test/test_b.jl"), 1, "test_b", Symbol[], "def")
            ic_a = ItemCoverage(ref_a, [1], Int[], Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                abspath("src/lib.jl") => ([1], Int[]),
            ))
            ic_b = ItemCoverage(ref_b, [1], Int[], Dict())
            current_fp = Testimonial.compute_environment_fingerprint(pwd())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a, ref_b => ic_b),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
                current_fp,
            )
            save_index(index, ".testimonial/index.jls")

            # Modify test_a to trigger selection
            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 2 end""")
            run(`git add .`)
            run(`git commit -m "modify test_a"`)

            # Step 1: Detect incident — simulate a run where test_b failed
            # but was NOT selected (test_a was selected, test_b was not)
            selected = [ref_a]
            all_items = [ref_a, ref_b]
            failed_items = [ref_b]  # test_b failed but wasn't selected
            incidents = Testimonial.compare_selection_vs_outcomes(
                selected, all_items, failed_items, "src/lib.jl",
            )
            @test length(incidents) == 1
            @test incidents[1].status == Candidate

            # Step 2: Save incidents
            save_incidents(incidents)
            @test isfile(Testimonial.INCIDENTS_PATH)

            # Step 3: Simulate 2 more occurrences (same content, same test)
            for _ in 1:2
                new_inc = MissedSelectionIncident("src/lib.jl", ref_b, now(), Candidate)
                append_incident(new_inc)
            end

            # Step 4: Load and promote — threshold=3, all 3 have same key
            # (content="src/lib.jl", test=test_b) → should promote
            loaded = load_incidents()
            @test length(loaded) == 3
            promoted = Testimonial.promote_incidents(loaded)
            promoted_count = count(i -> i.status == Promoted, promoted)
            @test promoted_count == 3

            # Step 5: Create manual edges from promoted incidents
            edges = create_manual_edges_from_promoted(promoted)
            @test length(edges) == 1
            @test edges[1].content_path == "src/lib.jl"
            @test edges[1].test == ref_b

            # Step 6: Verify manual edge forces selection
            # Modify src/lib.jl (not test_a.jl) — the manual edge should
            # force test_b to be selected even though the index doesn't
            # connect src/lib.jl to any test
            # (We need to commit a change to src/lib.jl)
            write("src/lib.jl", "module Lib; end")
            run(`git add .`)
            run(`git commit -m "modify src/lib.jl"`)

            # With enforcing mode, run() should include test_b via manual edge
            result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test result isa Vector
            result_names = Set(r.item.name for r in result)
            @test "test_b" in result_names
            @test any(
                any(rr.kind == AlwaysRun for rr in r.reasons)
                for r in result if r.item.name == "test_b"
            )
        end
    end
end

@testset "lifecycle: dismissed incidents are not promoted" begin
    mktempdir() do dir
        cd(dir) do
            ref = TestItemRef("test/foo.jl", 1, "test_foo")

            # Create 3 incidents for same key
            incs = [
                MissedSelectionIncident("src/lib.jl", ref, now(), Candidate),
                MissedSelectionIncident("src/lib.jl", ref, now(), Candidate),
                MissedSelectionIncident("src/lib.jl", ref, now(), Candidate),
            ]
            save_incidents(incs)

            # Dismiss the first two via CLI
            Testimonial.CLI.main(["incidents", "dismiss", "1"])
            Testimonial.CLI.main(["incidents", "dismiss", "1"])  # second is now at index 1

            remaining = load_incidents()
            @test length(remaining) == 1
            @test remaining[1].status == Candidate

            # Promote — only 1 incident left, below threshold
            promoted = Testimonial.promote_incidents(remaining)
            @test promoted[1].status == Candidate
        end
    end
end

@testset "lifecycle: multiple content paths are independent" begin
    mktempdir() do dir
        cd(dir) do
            ref = TestItemRef("test/foo.jl", 1, "test_foo")

            # Incidents for two different content paths
            incs = [
                MissedSelectionIncident("src/lib.jl", ref, now(), Candidate),
                MissedSelectionIncident("src/lib.jl", ref, now(), Candidate),
                MissedSelectionIncident("src/lib.jl", ref, now(), Candidate),
                MissedSelectionIncident("src/other.jl", ref, now(), Candidate),
                MissedSelectionIncident("src/other.jl", ref, now(), Candidate),
            ]
            save_incidents(incs)

            # Promote
            promoted = Testimonial.promote_incidents(incs)
            edges = create_manual_edges_from_promoted(promoted)

            # Only src/lib.jl has 3 occurrences → promoted → edge created
            @test length(edges) == 1
            @test edges[1].content_path == "src/lib.jl"

            # src/other.jl has only 2 → not promoted → no edge
            @test !any(e.content_path == "src/other.jl" for e in edges)
        end
    end
end

@testset "full pipeline smoke test: detect → reconcile → promote → verify" begin
    Testimonial.reset_flaky_history()
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 1 end""")
            write("test/test_b.jl", """@testitem "test_b" begin @test 1 == 1 end""")
            write("src/lib.jl", "# placeholder\n")
            run(`git add .`)
            run(`git commit -m "initial"`)

            # Build index with both items
            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            ref_b = TestItemRef(abspath("test/test_b.jl"), 1, "test_b", Symbol[], "def")
            ic_a = ItemCoverage(ref_a, [1], Int[], Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                abspath("src/lib.jl") => ([1], Int[]),
            ))
            ic_b = ItemCoverage(ref_b, [1], Int[], Dict())
            fp = Testimonial.compute_environment_fingerprint(dir)
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a, ref_b => ic_b),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
                fp,
            )
            save_index(index, ".testimonial/index.jls")

            # Modify test_a to trigger selection
            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 2 end""")
            run(`git add .`)
            run(`git commit -m "modify test_a"`)

            # Step 1: Run selection — should select test_a (changed)
            result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test result isa Vector
            @test any(r.item.name == "test_a" for r in result)

            # Step 2: Simulate a full run where test_b failed (but wasn't selected)
            selected_refs = [r.item for r in result]
            all_items = [ref_a, ref_b]
            failed_items = [ref_b]
            changed_content = "src/lib.jl"

            # Step 3: Reconcile — 3 times to trigger promotion
            for i in 1:3
                report = Testimonial.reconcile(selected_refs, all_items, failed_items, changed_content)
                if i == 1
                    @test report.incidents_detected == 1
                    @test report.incidents_promoted == 0
                elseif i == 3
                    @test report.incidents_detected == 1
                    @test report.incidents_promoted == 3
                end
            end

            # Step 4: Verify manual edge was created
            edges = load_manual_edges()
            @test length(edges) == 1
            @test edges[1].content_path == "src/lib.jl"
            @test edges[1].test == ref_b

            # Step 5: Verify reconciliation report was persisted
            report_dir = joinpath(".testimonial", "reconciliation")
            @test isdir(report_dir)
            entries = readdir(report_dir)
            @test length(entries) == 3  # 3 reconciles = 3 reports

            # Step 6: Verify index_info shows promotion readiness
            info = Testimonial.CLI.index_info()
            @test info.candidate_count == 0
            @test info.promoted_count == 3
            @test info.manual_edge_count == 1

            # Step 7: Now modify src/lib.jl and run — manual edge should force test_b
            write("src/lib.jl", "module Lib; end")
            run(`git add .`)
            run(`git commit -m "modify src/lib.jl"`)
            result2 = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test result2 isa Vector
            @test any(r.item.name == "test_b" for r in result2)
            @test any(
                any(rr.kind == AlwaysRun for rr in r.reasons)
                for r in result2 if r.item.name == "test_b"
            )
        end
    end
end
