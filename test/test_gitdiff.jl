# Testimonial.jl — Tests for GitDiff.jl (parse_unified_diff)
#
# Tests the unified diff parser across multiple scenarios:
# simple changes, new files, deleted files, renamed files,
# multiple hunks, empty diffs, and edge cases.
#
# See SEL-001 in openspec/changes/implement-coverage-layer/specs/smart-selection/spec.md

using Testimonial
using Test

# ── Helper ──────────────────────────────────────

"""
    make_diff(headers, hunk_lines...) -> String

Build a complete unified diff string. `headers` is a vector of header lines
(excluding the trailing newline), and each hunk_lines is a vector of hunk
content lines. Returns a single diff string terminated by newline.
"""
function make_diff(headers, hunks...)
    buf = IOBuffer()
    for h in headers
        write(buf, h, "\n")
    end
    for hunk in hunks
        for line in hunk
            write(buf, line, "\n")
        end
    end
    return String(take!(buf))
end

# ── Basic diff parsing ─────────────────────────

@testset "parse_unified_diff: simple single-file change" begin
    # A file with one line removed (line 5) and two lines added (lines 10, 11)
    diff = make_diff(
        ["diff --git a/src/foo.jl b/src/foo.jl",
         "--- a/src/foo.jl",
         "+++ b/src/foo.jl"],
        ["@@ -5,1 +5,3 @@",
         " context_5",
         "+new_line_10",
         "+new_line_11"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    # Should find the absolute path for src/foo.jl
    abs_path = abspath(joinpath(pwd(), "src/foo.jl"))
    @test haskey(result, abs_path)
    # Context line 5 is not added; new lines 6 and 7 are the + lines
    @test 6 in result[abs_path]
    @test 7 in result[abs_path]
    @test !(5 in result[abs_path])  # context line not counted
end

@testset "parse_unified_diff: multiple files changed" begin
    diff1 = make_diff(
        ["diff --git a/src/a.jl b/src/a.jl",
         "--- a/src/a.jl",
         "+++ b/src/a.jl"],
        ["@@ -1,1 +1,2 @@",
         " context",
         "+new_line"]
    )
    diff2 = make_diff(
        ["diff --git a/src/b.jl b/src/b.jl",
         "--- a/src/b.jl",
         "+++ b/src/b.jl"],
        ["@@ -5,1 +5,1 @@",
         "-old",
         "+new"]
    )
    full_diff = diff1 * diff2

    result = Testimonial.parse_unified_diff(full_diff, pwd())

    abs_a = abspath(joinpath(pwd(), "src/a.jl"))
    abs_b = abspath(joinpath(pwd(), "src/b.jl"))

    @test haskey(result, abs_a)
    @test haskey(result, abs_b)
    @test length(result) == 2
end

@testset "parse_unified_diff: new file" begin
    diff = make_diff(
        ["diff --git a/src/new_file.jl b/src/new_file.jl",
         "new file mode 100644",
         "index 0000000..abc1234",
         "--- /dev/null",
         "+++ b/src/new_file.jl"],
        ["@@ -0,0 +1,3 @@",
         "+line1",
         "+line2",
         "+line3"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    abs_path = abspath(joinpath(pwd(), "src/new_file.jl"))
    @test haskey(result, abs_path)
    @test 1 in result[abs_path]
    @test 2 in result[abs_path]
    @test 3 in result[abs_path]
end

@testset "parse_unified_diff: deleted file omitted" begin
    diff = make_diff(
        ["diff --git a/src/deleted.jl b/src/deleted.jl",
         "deleted file mode 100644",
         "index abc1234..0000000",
         "--- a/src/deleted.jl",
         "+++ /dev/null"],
        ["@@ -1,2 +0,0 @@",
         "-line1",
         "-line2"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    @test isempty(result)  # deleted files are not included
end

@testset "parse_unified_diff: renamed file (no content changes)" begin
    diff = make_diff(
        ["diff --git a/src/old_name.jl b/src/new_name.jl",
         "similarity index 100%",
         "rename from src/old_name.jl",
         "rename to src/new_name.jl"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    # Pure rename with no content changes → empty result
    @test isempty(result)
end

@testset "parse_unified_diff: renamed file with content changes" begin
    diff = make_diff(
        ["diff --git a/src/old_name.jl b/src/new_name.jl",
         "similarity index 80%",
         "rename from src/old_name.jl",
         "rename to src/new_name.jl",
         "--- a/src/old_name.jl",
         "+++ b/src/new_name.jl"],
        ["@@ -1,1 +1,2 @@",
         " context",
         "+added_line"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    abs_path = abspath(joinpath(pwd(), "src/new_name.jl"))
    @test haskey(result, abs_path)
    @test 2 in result[abs_path]
end

# ── Hunk edge cases ────────────────────────────

@testset "parse_unified_diff: multiple hunks per file" begin
    diff = make_diff(
        ["diff --git a/src/foo.jl b/src/foo.jl",
         "--- a/src/foo.jl",
         "+++ b/src/foo.jl"],
        ["@@ -10,1 +10,2 @@",
         " context_10",
         "+added_at_11"],
        ["@@ -20,1 +20,1 @@",
         "-old_at_20",
         "+new_at_20"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    abs_path = abspath(joinpath(pwd(), "src/foo.jl"))
    @test haskey(result, abs_path)
    @test 11 in result[abs_path]  # from first hunk: line 10 is context, 11 is added
    @test 20 in result[abs_path]  # from second hunk: line 20 is replaced
    @test length(result[abs_path]) == 2
end

@testset "parse_unified_diff: only deletions in a file" begin
    diff = make_diff(
        ["diff --git a/src/bar.jl b/src/bar.jl",
         "--- a/src/bar.jl",
         "+++ b/src/bar.jl"],
        ["@@ -5,2 +5,0 @@",
         "-line5",
         "-line6"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    # File with only deletions should not be in the result
    abs_path = abspath(joinpath(pwd(), "src/bar.jl"))
    @test !haskey(result, abs_path)
end

@testset "parse_unified_diff: context-only lines not counted" begin
    diff = make_diff(
        ["diff --git a/src/only_ctx.jl b/src/only_ctx.jl",
         "--- a/src/only_ctx.jl",
         "+++ b/src/only_ctx.jl"],
        ["@@ -1,3 +1,3 @@",
         " unchanged_1",
         " unchanged_2",
         " unchanged_3"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    # Context-only diff should produce no changes
    abs_path = abspath(joinpath(pwd(), "src/only_ctx.jl"))
    @test !haskey(result, abs_path)
end

# ── Empty / edge cases ─────────────────────────

@testset "parse_unified_diff: empty diff string" begin
    result = Testimonial.parse_unified_diff("", pwd())

    @test isempty(result)
end

@testset "parse_unified_diff: diff with no Julia files" begin
    diff = make_diff(
        ["diff --git a/README.md b/README.md",
         "--- a/README.md",
         "+++ b/README.md"],
        ["@@ -1,1 +1,2 @@",
         " old",
         "+new"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    @test isempty(result)
end

@testset "parse_unified_diff: binary files are ignored" begin
    diff = make_diff(
        ["diff --git a/image.png b/image.png",
         "index abc..def 100644",
         "Binary files a/image.png and b/image.png differ"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    @test isempty(result)
end

@testset "parse_unified_diff: Project.toml changes are included" begin
    diff = make_diff(
        ["diff --git a/Project.toml b/Project.toml",
         "--- a/Project.toml",
         "+++ b/Project.toml"],
        ["@@ -1,1 +1,2 @@",
         " name = \"Testimonial\"",
         "+new_dep"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    abs_path = abspath(joinpath(pwd(), "Project.toml"))
    @test haskey(result, abs_path)
    @test 2 in result[abs_path]
end

@testset "parse_unified_diff: Manifest.toml changes are included" begin
    diff = make_diff(
        ["diff --git a/Manifest.toml b/Manifest.toml",
         "--- a/Manifest.toml",
         "+++ b/Manifest.toml"],
        ["@@ -10,1 +10,1 @@",
         "-old_version = \"1.0\"",
         "+new_version = \"2.0\""]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    abs_path = abspath(joinpath(pwd(), "Manifest.toml"))
    @test haskey(result, abs_path)
end

# ── Path resolution ────────────────────────────

@testset "parse_unified_diff: relative paths resolved to absolute" begin
    diff = make_diff(
        ["diff --git a/src/relative.jl b/src/relative.jl",
         "--- a/src/relative.jl",
         "+++ b/src/relative.jl"],
        ["@@ -5,1 +5,1 @@",
         "-old",
         "+new"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    for path in keys(result)
        @test isabspath(path)
    end
end

@testset "parse_unified_diff: paths with subdirectory prefix" begin
    # Diff paths use a/ and b/ prefix which should be stripped
    diff = make_diff(
        ["diff --git a/src/lib/util.jl b/src/lib/util.jl",
         "--- a/src/lib/util.jl",
         "+++ b/src/lib/util.jl"],
        ["@@ -1,1 +1,1 @@",
         "-old",
         "+new"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    abs_path = abspath(joinpath(pwd(), "src/lib/util.jl"))
    @test haskey(result, abs_path)
end

# ── Realistic diff ─────────────────────────────

@testset "parse_unified_diff: realistic multi-file PR diff" begin
    diff = make_diff(
        ["diff --git a/src/bs.jl b/src/bs.jl",
         "--- a/src/bs.jl",
         "+++ b/src/bs.jl"],
        ["@@ -42,2 +42,4 @@",
         "     d1 = (log(S / K) + (r + sigma^2 / 2) * T) / (sigma * sqrt(T))",
         "+    # Add margin check",
         "+    if S <= 0; return 0.0; end",
         "     d2 = d1 - sigma * sqrt(T)"],
        ["diff --git a/test/test_bs.jl b/test/test_bs.jl",
         "--- a/test/test_bs.jl",
         "+++ b/test/test_bs.jl"],
        ["@@ -10,1 +10,5 @@",
         " @testitem \"Black-Scholes call\" begin",
         "+    @test black_scholes_call(100.0, 100.0, 0.05, 1.0, 0.2) ≈ 10.45 atol=0.01",
         "+    @test black_scholes_call(0.0, 100.0, 0.05, 1.0, 0.2) == 0.0",
         "+end",
         "+",
         "+@testitem \"Black-Scholes put\" begin"],
        ["diff --git a/README.md b/README.md",
         "--- a/README.md",
         "+++ b/README.md"],
        ["@@ -1,1 +1,1 @@",
         "-old readme",
         "+new readme"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    # Two Julia files changed, one README ignored
    @test length(result) == 2

    abs_bs = abspath(joinpath(pwd(), "src/bs.jl"))
    abs_test_bs = abspath(joinpath(pwd(), "test/test_bs.jl"))

    @test haskey(result, abs_bs)
    @test haskey(result, abs_test_bs)

    # bs.jl: lines 43 and 44 added (after context line 42)
    @test 43 in result[abs_bs]
    @test 44 in result[abs_bs]

    # test_bs.jl: lines 11-14 added (after context line 10)
    @test 11 in result[abs_test_bs]
    @test 12 in result[abs_test_bs]
    @test 13 in result[abs_test_bs]
    @test 14 in result[abs_test_bs]
end

# ── No newline at end of file ──────────────────

@testset "parse_unified_diff: no newline at end of file" begin
    diff = make_diff(
        ["diff --git a/src/foo.jl b/src/foo.jl",
         "--- a/src/foo.jl",
         "+++ b/src/foo.jl"],
        ["@@ -1,1 +1,2 @@",
         " context",
         "+new_last_line",
         "\\ No newline at end of file"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    abs_path = abspath(joinpath(pwd(), "src/foo.jl"))
    @test haskey(result, abs_path)
    @test 2 in result[abs_path]
end

# ── Edge: hunk with only additions at file start ──

@testset "parse_unified_diff: additions at file start (non-new file)" begin
    diff = make_diff(
        ["diff --git a/src/foo.jl b/src/foo.jl",
         "--- a/src/foo.jl",
         "+++ b/src/foo.jl"],
        ["@@ -1,0 +1,2 @@",
         "+preamble_line_1",
         "+preamble_line_2"]
    )

    result = Testimonial.parse_unified_diff(diff, pwd())

    abs_path = abspath(joinpath(pwd(), "src/foo.jl"))
    @test haskey(result, abs_path)
    @test 1 in result[abs_path]
    @test 2 in result[abs_path]
end