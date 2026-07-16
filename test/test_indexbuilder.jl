# Testimonial.jl — Tests for IndexBuilder record_item
#
# Verifies the single-item recording API works end-to-end.
# Integration tests for actual subprocess spawning are in test_wah.jl.
#
# See REC-007 and task 6.3 in
# openspec/changes/implement-coverage-layer/tasks.md

using Testimonial
using Test

@testset "record_item returns ItemCoverage" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_foo.jl")
        write(test_file, """
        @testitem "my_test" begin
            @test 1 == 1
        end
        """)

        result = Testimonial.record_item(test_file, "my_test")
        @test result isa Testimonial.ItemCoverage
        @test result.item.name == "my_test"
    end
end

@testset "record_item returns nothing for unknown item" begin
    mktempdir() do dir
        test_file = joinpath(dir, "test_bar.jl")
        write(test_file, """
        @testitem "known" begin
            @test 1 == 1
        end
        """)

        result = Testimonial.record_item(test_file, "unknown")
        @test result === nothing
    end
end

@testset "record_item fails for nonexistent file" begin
    @test_throws Exception Testimonial.record_item("/nonexistent/path.jl", "foo")
end