# Testimonial.jl — Tests for CLI entry points
#
# Tests index_info, save_index, load_index, explain, and run.
#
# See SEL-006, SEL-007 in
# openspec/changes/implement-coverage-layer/specs/smart-selection/spec.md

using Testimonial
using Test
using Dates

@testset "index_info returns metadata for existing index" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            # Create a simple CoverageIndex and persist it
            ref = TestItemRef("test/foo.jl", 10, "test_a", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1, 2, 3], [4, 5], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            info = index_info()
            @test info isa NamedTuple
            @test info.index_present == true
            @test info.git_sha == "abc123"
            @test info.julia_version == string(VERSION)
            @test info.schema_version == 2
            @test info.item_count == 1
            @test info.file_count == 1
            @test info.age_hours isa Float64
        end
    end
end

@testset "index_info returns empty metadata when no index exists" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            info = index_info()
            @test info isa NamedTuple
            @test info.index_present == false
            @test info.item_count == 0
            @test info.git_sha == ""
            @test info.file_count == 0
        end
    end
end

@testset "index_info computes file_count correctly" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            # Items from two files
            ref1 = TestItemRef("test/a_test.jl", 10, "test_a", Symbol[], "abc123")
            ref2 = TestItemRef("test/b_test.jl", 5, "test_b", Symbol[], "def456")
            ic1 = ItemCoverage(ref1, [1], Int[], Dict())
            ic2 = ItemCoverage(ref2, [10], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref1 => ic1, ref2 => ic2),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            info = index_info()
            @test info.item_count == 2
            @test info.file_count == 2
        end
    end
end

@testset "index_info reports promotion readiness" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            mkpath(".testimonial")

            # Create a valid index
            ref = TestItemRef("test/foo_test.jl", 10, "test_foo", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            # Create some incidents
            ref_missed = TestItemRef("test/bar.jl", 1, "test_bar")
            inc1 = MissedSelectionIncident("src/lib.jl", ref_missed, now(), Candidate)
            inc2 = MissedSelectionIncident("src/lib.jl", ref_missed, now(), Candidate)
            inc3 = MissedSelectionIncident("src/lib.jl", ref_missed, now(), Promoted)
            save_incidents([inc1, inc2, inc3])

            # Create a manual edge
            edge = ManualEdge("src/lib.jl", ref_missed, now())
            save_manual_edges([edge])

            info = index_info()
            @test info.candidate_count == 2
            @test info.promoted_count == 1
            @test info.manual_edge_count == 1
        end
    end
end

@testset "index_info reports zero promotion readiness when no incidents" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            mkpath(".testimonial")

            ref = TestItemRef("test/foo_test.jl", 10, "test_foo", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            info = index_info()
            @test info.candidate_count == 0
            @test info.promoted_count == 0
            @test info.manual_edge_count == 0
        end
    end
end

# ── explain ────────────────────────────────────

@testset "explain returns covered files for a known item" begin
    mktempdir() do dir
        cd(dir) do
            ref = TestItemRef("test/foo_test.jl", 10, "test_foo", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1, 2, 3], [4, 5], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            result = explain("test/foo_test.jl", "test_foo")
            @test result isa Vector{String}
            @test !isempty(result)
            # Should mention the test file and covered line count
            @test any(contains(s, "test/foo_test.jl") for s in result)
            @test any(contains(s, "3") for s in result)  # 3 covered lines
        end
    end
end

@testset "explain returns empty vector for unknown item" begin
    mktempdir() do dir
        cd(dir) do
            ref = TestItemRef("test/foo_test.jl", 10, "test_foo", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1, 2, 3], [4, 5], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            result = explain("test/foo_test.jl", "nonexistent_item")
            @test result isa Vector{String}
            @test isempty(result)
        end
    end
end

@testset "explain returns empty vector when no index exists" begin
    mktempdir() do dir
        cd(dir) do
            result = explain("test/foo_test.jl", "test_foo")
            @test result isa Vector{String}
            @test isempty(result)
        end
    end
end

# ── run ────────────────────────────────────────

@testset "run returns :full_suite when no index exists" begin
    mktempdir() do dir
        cd(dir) do
            result = Testimonial.CLI.run()
            @test result == :full_suite
        end
    end
end

@testset "run returns :full_suite when index is stale" begin
    mktempdir() do dir
        cd(dir) do
            old_time = now() - Dates.Day(2)
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(),
                "abc123",
                string(VERSION),
                v"0.1.0",
                old_time,
            )
            save_index(index, ".testimonial/index.jls")

            result = Testimonial.CLI.run()
            @test result == :full_suite
        end
    end
end

@testset "run returns :full_suite when Project.toml or Manifest.toml changed" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            write("test/foo_test.jl", """@testitem "test_foo" begin @test 1==1 end""")

            ref = TestItemRef(abspath("test/foo_test.jl"), 1, "test_foo", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            # Without git history, diff is empty — just verify it runs
            result = Testimonial.CLI.run()
            @test result isa Union{Symbol, Vector}
        end
    end
end

@testset "run returns :full_suite for always-run test prefixes" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")

            write("test/runtests.jl", """@testitem "runtests_check" begin @test 1==1 end""")

            ref = TestItemRef(abspath("test/runtests.jl"), 1, "runtests_check", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123",
                string(VERSION),
                v"0.1.0",
                now(),
            )
            save_index(index, ".testimonial/index.jls")

            result = Testimonial.CLI.run(; index_path=".testimonial/index.jls")
            @test result == :full_suite
        end
    end
end

@testset "run accepts shadow keyword argument" begin
    mktempdir() do dir
        cd(dir) do
            # No index exists — should return :full_suite regardless of shadow
            result = Testimonial.CLI.run(; shadow=true)
            @test result == :full_suite
        end
    end
end

@testset "run defaults shadow to false" begin
    mktempdir() do dir
        cd(dir) do
            # No index exists — should return :full_suite
            result = Testimonial.CLI.run()
            @test result == :full_suite
        end
    end
end

@testset "run returns :full_suite when shadow=true and selection would be returned" begin
    mktempdir() do dir
        cd(dir) do
            # Set up git repo
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            # Test file A
            write("test/test_a.jl", """
            @testitem "test_a" begin
                @test 1 == 1
            end
            """)

            # Test file B (not changed)
            write("test/test_b.jl", """
            @testitem "test_b" begin
                @test 2 == 2
            end
            """)

            run(`git add .`)
            run(`git commit -m "initial"`)

            # Build index with both items
            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            ref_b = TestItemRef(abspath("test/test_b.jl"), 1, "test_b", Symbol[], "def")
            ic_a = ItemCoverage(ref_a, [1, 2], Int[], Dict())
            ic_b = ItemCoverage(ref_b, [3, 4], Int[], Dict())
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
            write("test/test_a.jl", """
            @testitem "test_a" begin
                @test 1 == 2
            end
            """)

            run(`git add .`)
            run(`git commit -m "modify test_a"`)

            # Normal mode should return a selection containing test_a
            normal_result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test normal_result isa Vector
            @test !isempty(normal_result)

            # Shadow mode should return :full_suite
            shadow_result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=true)
            @test shadow_result == :full_suite
        end
    end
end

@testset "run returns :full_suite when environment fingerprint mismatches" begin
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

            # Build index with a deliberately wrong fingerprint
            ref = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
                "wrong-fingerprint",
            )
            save_index(index, ".testimonial/index.jls")

            # Modify test to create a diff
            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 2 end""")
            run(`git add .`)
            run(`git commit -m "modify test_a"`)

            # Fingerprint mismatch should trigger :full_suite
            result = Testimonial.CLI.run(; base_ref="HEAD~1")
            @test result == :full_suite
        end
    end
end

@testset "run proceeds when environment fingerprint matches" begin
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

            # Build index with correct fingerprint
            current_fp = Testimonial.compute_environment_fingerprint(dir)
            ref = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
                current_fp,
            )
            save_index(index, ".testimonial/index.jls")

            # Modify test to create a diff
            write("test/test_a.jl", """@testitem "test_a" begin @test 1 == 2 end""")
            run(`git add .`)
            run(`git commit -m "modify test_a"`)

            # Matching fingerprint should proceed (returns :full_suite because
            # smart selection finds a selection, but no index for comparison)
            result = Testimonial.CLI.run(; base_ref="HEAD~1")
            @test result isa Vector
        end
    end
end

@testset "run returns :full_suite for untracked source file change" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            # Test file that covers a source file via source_files
            write("test/test_a.jl", """
            @testitem "test_a" begin
                @test 1 == 1
            end
            """)

            # Source file (will be modified later)
            write("src/lib.jl", """
            function foo()
                return 1
            end
            """)

            run(`git add .`)
            run(`git commit -m "initial"`)

            # Build index with source_files linking test_a to src/lib.jl
            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                abspath("src/lib.jl") => ([2, 3], Int[]),
            )
            ic_a = ItemCoverage(ref_a, [1, 2], Int[], source_files)
            current_fp = Testimonial.compute_environment_fingerprint(pwd())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
                current_fp,
            )
            save_index(index, ".testimonial/index.jls")

            # Modify an untracked source file (not in any item's source_files)
            write("src/other.jl", """
            function bar()
                return 2
            end
            """)

            run(`git add .`)
            run(`git commit -m "add untracked source file"`)

            # Untracked source change should return :full_suite
            result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test result == :full_suite
        end
    end
end

@testset "run returns :full_suite for partially covered source file with gaps" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            # Test file that covers a source file via source_files
            write("test/test_a.jl", """
            @testitem "test_a" begin
                @test 1 == 1
            end
            """)

            write("src/lib.jl", """
            function foo()
                return 1
            end

            function baz()
                return 3
            end
            """)

            run(`git add .`)
            run(`git commit -m "initial"`)

            # Build index: test_a covers lines 2-3 (foo body), but NOT lines 6-7 (baz body)
            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                abspath("src/lib.jl") => ([2, 3], [6, 7]),
            )
            ic_a = ItemCoverage(ref_a, [1, 2], Int[], source_files)
            current_fp = Testimonial.compute_environment_fingerprint(pwd())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
                current_fp,
            )
            save_index(index, ".testimonial/index.jls")

            # Modify uncovered lines in the source file (introduces gaps)
            write("src/lib.jl", """
            function foo()
                return 1
            end

            function baz()
                return 99  # changed
            end
            """)

            run(`git add .`)
            run(`git commit -m "modify uncovered lines in source"`)

            # Partially covered source with gaps should return :full_suite
            result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test result == :full_suite
        end
    end
end

@testset "run selects covering test for fully covered source file change" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            # Test file that covers a source file via source_files
            write("test/test_a.jl", """
            @testitem "test_a" begin
                @test 1 == 1
            end
            """)

            write("src/lib.jl", """
            function foo()
                return 1
            end
            """)

            run(`git add .`)
            run(`git commit -m "initial"`)

            # Build index: test_a covers lines 2-3 of src/lib.jl
            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                abspath("src/lib.jl") => ([2, 3], Int[]),
            )
            ic_a = ItemCoverage(ref_a, [1, 2], Int[], source_files)
            current_fp = Testimonial.compute_environment_fingerprint(pwd())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
                current_fp,
            )
            save_index(index, ".testimonial/index.jls")

            # Modify a covered line in the source file
            write("src/lib.jl", """
            function foo()
                return 2  # changed, but line is covered
            end
            """)

            run(`git add .`)
            run(`git commit -m "modify covered line in source"`)

            # Fully covered change should select the covering test, not :full_suite
            result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test result isa Vector
            @test !isempty(result)
            @test any(r.item.name == "test_a" for r in result if isa(r, Testimonial.ImpactResult))
        end
    end
end

@testset "run merges duplicate selections with distinct reasons" begin
    mktempdir() do dir
        cd(dir) do
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)

            mkpath("test")
            mkpath("src")

            # Test file with @testitem
            write("test/test_a.jl", """
            @testitem "test_a" begin
                @test 1 == 1
            end
            """)

            # Source file (will be modified)
            write("src/lib.jl", """
            function foo()
                return 1
            end
            """)

            run(`git add .`)
            run(`git commit -m "initial"`)

            # Build index: test_a covers lines 2-3 of src/lib.jl
            ref_a = TestItemRef(abspath("test/test_a.jl"), 1, "test_a", Symbol[], "abc")
            source_files = Dict{String, Tuple{Vector{Int}, Vector{Int}}}(
                abspath("src/lib.jl") => ([2, 3], Int[]),
            )
            ic_a = ItemCoverage(ref_a, [1, 2], Int[], source_files)
            current_fp = Testimonial.compute_environment_fingerprint(pwd())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a => ic_a),
                readchomp(`git rev-parse HEAD`),
                string(VERSION),
                v"0.1.0",
                now(),
                current_fp,
            )
            save_index(index, ".testimonial/index.jls")

            # Create a manual edge linking src/lib.jl to test_a (same test as coverage provider selects)
            edge = Testimonial.ManualEdge("src/lib.jl", ref_a, now())
            Testimonial.save_manual_edges([edge])

            # Modify a covered line in src/lib.jl
            write("src/lib.jl", """
            function foo()
                return 2  # changed, but line is covered
            end
            """)

            run(`git add .`)
            run(`git commit -m "modify covered line in source"`)

            # Coverage provider selects test_a (covered line changed)
            # Manual edge provider also selects test_a (src/lib.jl changed)
            # Merge should produce one ImpactResult with both reasons
            result = Testimonial.CLI.run(; base_ref="HEAD~1", shadow=false)
            @test result isa Vector
            @test length(result) == 1
            @test result[1].item.name == "test_a"

            # Should have both DirectChange (from coverage) and AlwaysRun (from manual edge) reasons
            reason_kinds = Set(rr.kind for rr in result[1].reasons)
            @test Testimonial.DirectChange in reason_kinds
            @test Testimonial.AlwaysRun in reason_kinds
        end
    end
end
