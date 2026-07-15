# Testimonial.jl — Tests for Persistence.jl (atomic write)

@testset "atomic_write" begin
    mktempdir() do dir
        path = joinpath(dir, "test.json")

        # Basic write
        data = "hello world"
        Testimonial.atomic_write(path, data)
        @test isfile(path)
        @test read(path, String) == data

        # Overwrite
        data2 = "goodbye"
        Testimonial.atomic_write(path, data2)
        @test read(path, String) == data2

        # Nested directory creation
        nested = joinpath(dir, "a", "b", "c", "nested.json")
        Testimonial.atomic_write(nested, "nested")
        @test isfile(nested)
        @test read(nested, String) == "nested"

        # Empty content
        empty_path = joinpath(dir, "empty.json")
        Testimonial.atomic_write(empty_path, "")
        @test read(empty_path, String) == ""

        # No .tmp file left behind
        leftovers = filter(f -> endswith(f, ".tmp"), readdir(dir))
        @test isempty(leftovers)
    end
end