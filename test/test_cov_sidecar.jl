# Testimonial.jl — Tests for .jl.cov sidecar parsing
#
# Verifies that Julia code coverage sidecar files are correctly parsed
# and converted to Dict{String, Set{Int}} of covered line numbers.
#
# See REC-002 (coverage sidecar parsing) in
# openspec/changes/implement-coverage-layer/specs/recording/spec.md

using Testimonial
using Test

# Helper to build a .jl.cov file line with proper column alignment
# Format: columns 1-9 = coverage count, right-aligned in 9-char field
# column 9 = '-' for non-executable, digit for count
# column 10 = space, then linenum:code
function _cov_line(count_or_dash, linenum, code)
    count_str = count_or_dash == '-' ? "        -" : lpad(string(count_or_dash), 9)
    return count_str * " " * string(linenum) * ":" * code * "\n"
end

@testset "parse_cov_sidecar: basic coverage" begin
    mktempdir() do dir
        src_path = joinpath(dir, "test_foo.jl")
        write(src_path, "@testitem \"foo\" begin\n    @test 1 == 1\n    @test 2 == 2\nend\n")

        # Create matching .jl.cov file
        cov_path = src_path * ".cov"
        open(cov_path, "w") do f
            write(f, _cov_line('-', 1, "@testitem \"foo\" begin"))
            write(f, _cov_line(5, 2, "    @test 1 == 1"))
            write(f, _cov_line(3, 3, "    @test 2 == 2"))
            write(f, _cov_line('-', 4, "end"))
        end

        result = Testimonial.parse_cov_sidecar(src_path)
        @test result isa Dict{String, Set{Int}}
        @test haskey(result, src_path)
        @test result[src_path] == Set([2, 3])
    end
end

@testset "parse_cov_sidecar: only positive counts included" begin
    mktempdir() do dir
        src_path = joinpath(dir, "test_counts.jl")
        write(src_path, "@testitem \"counts\" begin\n    @test 1 == 1\n    x = 0\n    @test x == 0\nend\n")

        cov_path = src_path * ".cov"
        open(cov_path, "w") do f
            write(f, _cov_line('-', 1, "@testitem \"counts\" begin"))
            write(f, _cov_line(1, 2, "    @test 1 == 1"))
            write(f, _cov_line(0, 3, "    x = 0"))
            write(f, _cov_line(2, 4, "    @test x == 0"))
            write(f, _cov_line('-', 5, "end"))
        end

        result = Testimonial.parse_cov_sidecar(src_path)
        covered = result[src_path]
        @test 2 in covered
        @test 4 in covered
        @test !(3 in covered)
        @test !(1 in covered)
    end
end

@testset "parse_cov_sidecar: nonexistent file returns empty" begin
    result = Testimonial.parse_cov_sidecar("/nonexistent/path.jl")
    @test isempty(result)
end

@testset "parse_cov_sidecar: missing cov file returns empty" begin
    mktempdir() do dir
        src_path = joinpath(dir, "no_cov.jl")
        write(src_path, "x = 1")
        result = Testimonial.parse_cov_sidecar(src_path)
        @test isempty(result)
    end
end