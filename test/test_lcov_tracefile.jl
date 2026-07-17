# Testimonial.jl — Tests for LCOV tracefile parsing (Julia 1.12+)
#
# Verifies that Julia 1.12's LCOV-format tracefiles are correctly parsed
# and converted to Dict{String, Set{Int}} of covered line numbers.
#
# See REC-002 (coverage sidecar parsing) and testimonial-7vn0.

using Testimonial
using Test

# ── Helpers ─────────────────────────────────────

"""Build an LCOV tracefile record for a single source file."""
function _lcov_record(source_path, line_counts)
    lines = ["SF:$source_path"]
    for (lineno, count) in line_counts
        push!(lines, "DA:$lineno,$count")
    end
    push!(lines, "end_of_record")
    return join(lines, "\n") * "\n"
end

# ── Tests ───────────────────────────────────────

@testset "parse_lcov_tracefile: basic coverage" begin
    mktempdir() do dir
        tracefile = joinpath(dir, "tracefile.info")
        src_path = joinpath(dir, "test_foo.jl")

        write(tracefile, _lcov_record(src_path, [
            (2, 5),
            (3, 3),
            (4, 0),     # uncovered line — excluded
        ]))

        result = Testimonial.CoverageLayer._parse_lcov_tracefile(tracefile)
        @test result isa Dict{String, Set{Int}}
        @test haskey(result, src_path)
        @test result[src_path] == Set([2, 3])
    end
end

@testset "parse_lcov_tracefile: multiple source files" begin
    mktempdir() do dir
        tracefile = joinpath(dir, "tracefile.info")
        src1 = joinpath(dir, "src", "foo.jl")
        src2 = joinpath(dir, "src", "bar.jl")

        open(tracefile, "w") do f
            write(f, _lcov_record(src1, [
                (1, 1),
                (2, 0),
            ]))
            write(f, _lcov_record(src2, [
                (5, 7),
                (6, 2),
            ]))
        end

        result = Testimonial.CoverageLayer._parse_lcov_tracefile(tracefile)
        @test length(result) == 2
        @test result[src1] == Set([1])
        @test result[src2] == Set([5, 6])
    end
end

@testset "parse_lcov_tracefile: only positive counts included" begin
    mktempdir() do dir
        tracefile = joinpath(dir, "tracefile.info")
        src_path = joinpath(dir, "test_counts.jl")

        write(tracefile, _lcov_record(src_path, [
            (1, 1),
            (2, 0),
            (3, 2),
            (4, 0),
            (5, 0),
        ]))

        result = Testimonial.CoverageLayer._parse_lcov_tracefile(tracefile)
        covered = result[src_path]
        @test 1 in covered
        @test 3 in covered
        @test !(2 in covered)
        @test !(4 in covered)
        @test !(5 in covered)
    end
end

@testset "parse_lcov_tracefile: nonexistent file returns empty" begin
    result = Testimonial.CoverageLayer._parse_lcov_tracefile("/nonexistent/tracefile.info")
    @test isempty(result)
end

@testset "parse_lcov_tracefile: empty tracefile" begin
    mktempdir() do dir
        tracefile = joinpath(dir, "tracefile.info")
        write(tracefile, "")
        result = Testimonial.CoverageLayer._parse_lcov_tracefile(tracefile)
        @test isempty(result)
    end
end

@testset "parse_lcov_tracefile: no executable lines in tracefile" begin
    mktempdir() do dir
        tracefile = joinpath(dir, "tracefile.info")
        src_path = joinpath(dir, "empty.jl")

        write(tracefile, _lcov_record(src_path, [
            (1, 0),
            (2, 0),
        ]))

        result = Testimonial.CoverageLayer._parse_lcov_tracefile(tracefile)
        # Files with zero covered lines are not included in the result
        @test !haskey(result, src_path)
    end
end

@testset "parse_lcov_tracefile: malformed lines are skipped gracefully" begin
    mktempdir() do dir
        tracefile = joinpath(dir, "tracefile.info")
        src_path = joinpath(dir, "messy.jl")

        open(tracefile, "w") do f
            write(f, "SF:$src_path\n")
            write(f, "DA:1,5\n")
            write(f, "garbage line\n")
            write(f, "DA:2,3\n")
            write(f, "DA:not_a_number\n")
            write(f, "end_of_record\n")
        end

        result = Testimonial.CoverageLayer._parse_lcov_tracefile(tracefile)
        @test haskey(result, src_path)
        @test result[src_path] == Set([1, 2])
    end
end

@testset "parse_lcov_tracefile: no SF record before DA" begin
    mktempdir() do dir
        tracefile = joinpath(dir, "tracefile.info")
        open(tracefile, "w") do f
            write(f, "DA:1,5\n")
            write(f, "end_of_record\n")
        end

        result = Testimonial.CoverageLayer._parse_lcov_tracefile(tracefile)
        @test isempty(result)
    end
end

# ── Integration: parse_cov_sidecar with LCOV tracefile (Julia 1.12+) ──

@testset "parse_cov_sidecar: finds LCOV tracefile in parent directory" begin
    mktempdir() do dir
        subdir = joinpath(dir, "sub")
        mkpath(subdir)
        src_path = joinpath(subdir, "test_integration.jl")
        write(src_path, "x = 1\ny = 2\n")

        # Place tracefile in parent dir, not in subdir
        tracefile = joinpath(dir, "tracefile.info")
        write(tracefile, _lcov_record(src_path, [
            (1, 1),
            (2, 0),
        ]))

        result = Testimonial.parse_cov_sidecar(src_path)
        @test haskey(result, src_path)
        @test result[src_path] == Set([1])
    end
end

@testset "parse_cov_sidecar: no tracefile found returns empty" begin
    mktempdir() do dir
        src_path = joinpath(dir, "no_coverage.jl")
        write(src_path, "x = 1\n")

        # No tracefile.info in any parent directory
        result = Testimonial.parse_cov_sidecar(src_path)
        @test isempty(result)
    end
end