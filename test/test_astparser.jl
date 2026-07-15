# Testimonial.jl — Tests for ASTParser (file_hash, discover_testitems, tags)

using Test

@testset "file_hash" begin
    mktempdir() do dir
        # Basic hash of known content
        path = joinpath(dir, "test.jl")
        content = "module Foo\n@testitem \"bar\" begin\n    @test 1 == 1\nend\nend"
        write(path, content)
        # Returns a 12-char hex string
        hash = Testimonial.file_hash(path)
        @test hash isa String
        @test length(hash) == 12
        @test all(c -> c in "0123456789abcdef", hash)

        # Same content → same hash
        path2 = joinpath(dir, "test2.jl")
        write(path2, content)
        @test Testimonial.file_hash(path2) == Testimonial.file_hash(path)

        # Different content → different hash
        path3 = joinpath(dir, "test3.jl")
        content3 = "module Baz\n@testitem \"qux\" begin\n    @test 2 == 2\nend\nend"
        write(path3, content3)
        @test Testimonial.file_hash(path3) != Testimonial.file_hash(path)

        # Empty file
        path4 = joinpath(dir, "empty.jl")
        write(path4, "")
        @test length(Testimonial.file_hash(path4)) == 12

        # Non-existent file throws
        @test_throws SystemError Testimonial.file_hash(joinpath(dir, "nonexistent.jl"))
    end
end