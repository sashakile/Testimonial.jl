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

@testset "extract_tags" begin
    mktempdir() do dir
        path = joinpath(dir, "test.jl")

        # No tags
        write(path, """
        @testitem "foo" begin
            @test 1 == 1
        end
        """)
        @test Testimonial.extract_tags(path) == Dict("foo" => Symbol[])

        # With tags
        write(path, """
        @testitem "bar" tags=[:integration] begin
            @test 2 == 2
        end
        """)
        @test Testimonial.extract_tags(path) == Dict("bar" => [:integration])

        # Multiple tags
        write(path, """
        @testitem "baz" tags=[:integration, :slow] begin
            @test 3 == 3
        end
        """)
        @test Testimonial.extract_tags(path) == Dict("baz" => [:integration, :slow])

        # @testitem with external_inputs
        write(path, """
        @testitem "ext_test" external_inputs=["config/app.toml", "data/fixtures.csv"] begin
            @test 1 == 1
        end
        """)
        items = Testimonial.discover_testitems([dir])
        ext_idx = findfirst(i -> i.name == "ext_test", items)
        @test ext_idx !== nothing
        if ext_idx !== nothing
            ext_item = items[ext_idx]
            @test ext_item.external_inputs == ["config/app.toml", "data/fixtures.csv"]
        end

        # Multiple items in one file
        write(path, """
        @testitem "a" begin
            @test 1 == 1
        end
        @testitem "b" tags=[:unit] begin
            @test 2 == 2
        end
        @testitem "c" tags=[:integration, :slow] begin
            @test 3 == 3
        end
        """)
        tags = Testimonial.extract_tags(path)
        @test tags == Dict("a" => Symbol[], "b" => [:unit], "c" => [:integration, :slow])

        # Non-existent file throws
        @test_throws SystemError Testimonial.extract_tags(joinpath(dir, "nonexistent.jl"))
    end
end

@testset "discover_testitems" begin
    mktempdir() do dir
        # Single file, single item, no tags
        f1 = joinpath(dir, "test1.jl")
        write(f1, """
        module Test1
        @testitem "foo" begin
            @test 1 == 1
        end
        end
        """)
        f1_hash = Testimonial.file_hash(f1)

        items = Testimonial.discover_testitems([dir])
        @test length(items) == 1
        @test items[1].name == "foo"
        @test items[1].tags == Symbol[]
        @test items[1].file_hash == f1_hash
        @test endswith(items[1].file, "test1.jl")

        # Multiple items in one file, some with tags
        f2 = joinpath(dir, "test2.jl")
        write(f2, """
        module Test2
        @testitem "a" begin
            @test 1 == 1
        end
        @testitem "b" tags=[:unit] begin
            @test 2 == 2
        end
        @testitem "c" tags=[:integration, :slow] begin
            @test 3 == 3
        end
        end
        """)
        f2_hash = Testimonial.file_hash(f2)

        items = Testimonial.discover_testitems([dir])
        @test length(items) == 4  # 1 from f1 + 3 from f2

        # Find items by name
        by_name = Dict(item.name => item for item in items)

        @test haskey(by_name, "foo")
        @test by_name["foo"].tags == Symbol[]
        @test by_name["foo"].file_hash == f1_hash

        @test haskey(by_name, "a")
        @test by_name["a"].tags == Symbol[]
        @test by_name["a"].file_hash == f2_hash

        @test haskey(by_name, "b")
        @test by_name["b"].tags == [:unit]
        @test by_name["b"].file_hash == f2_hash

        @test haskey(by_name, "c")
        @test by_name["c"].tags == [:integration, :slow]
        @test by_name["c"].file_hash == f2_hash

        # Line numbers should be set
        for item in items
            @test item.line > 0
        end

        # Directory with no .jl files returns empty
        empty_dir = joinpath(dir, "empty")
        mkpath(empty_dir)
        @test Testimonial.discover_testitems([empty_dir]) == Testimonial.TestItemRef[]

        # Non-existent directory throws
        @test_throws Base.IOError Testimonial.discover_testitems([joinpath(dir, "nonexistent")])
    end
end

@testset "discover_testitems multi-line" begin
    mktempdir() do dir
        f1 = joinpath(dir, "multi.jl")
        write(f1, """
        @testitem "foo" tags=[:a,
            :b] begin
            @test 1 == 1
        end
        """)

        items = Testimonial.discover_testitems([dir])
        @test length(items) == 1
        @test items[1].name == "foo"
        @test items[1].tags == [:a, :b]
        @test items[1].line == 1  # @testitem is on line 1 of file content
    end
end

@testset "discover_testitems recursive" begin
    mktempdir() do dir
        # Top-level file
        top = joinpath(dir, "top.jl")
        write(top, """@testitem "top" begin @test 1 == 1 end""")

        # Subdirectory file
        sub = joinpath(dir, "sub")
        mkpath(sub)
        nested = joinpath(sub, "nested.jl")
        write(nested, """@testitem "nested" begin @test 2 == 2 end""")

        items = Testimonial.discover_testitems([dir])
        @test length(items) == 2
        names = sort([item.name for item in items])
        @test names == ["nested", "top"]
    end
end

@testset "discover_testitems with external_inputs and multi-byte chars" begin
    mktempdir() do dir
        path = joinpath(dir, "test.jl")

        # Box-drawing char (U+2500, 3 bytes) triggers StringIndexError
        # if string slicing is not UTF-8 safe
        write(path, """
        ────
        @testitem "foo" begin
            @test 1 == 1
        end

        @testitem "bar" external_inputs=["config/app.toml"] begin
            @test 2 == 2
        end
        """)
        items = Testimonial.discover_testitems([dir])
        @test length(items) == 2

        foo = items[findfirst(i -> i.name == "foo", items)]
        @test foo.external_inputs == String[]

        bar = items[findfirst(i -> i.name == "bar", items)]
        @test bar.external_inputs == ["config/app.toml"]
    end
end

@testset "discover_testsets: named @testset blocks" begin
    mktempdir() do dir
        path = joinpath(dir, "test_foo.jl")
        write(path, """
        @testset "My Test Suite" begin
            @test 1 == 1
            @test 2 == 2
        end
        """)
        items = Testimonial.discover_testsets([dir])
        @test length(items) == 1
        @test items[1].name == "My Test Suite"
        @test items[1].line == 1
        @test endswith(items[1].file, "test_foo.jl")
    end
end

@testset "discover_testsets: unnamed @testset begin" begin
    mktempdir() do dir
        path = joinpath(dir, "test_bar.jl")
        write(path, """
        @testset begin
            @test 1 == 1
        end
        """)
        items = Testimonial.discover_testsets([dir])
        @test length(items) == 1
        @test items[1].name == ""
        @test items[1].line == 1
    end
end

@testset "discover_testsets: @testset for loops" begin
    mktempdir() do dir
        path = joinpath(dir, "test_params.jl")
        write(path, """
        @testset for x in [1, 2, 3]
            @test x > 0
        end
        """)
        items = Testimonial.discover_testsets([dir])
        @test length(items) == 1
        @test items[1].name == ""
        @test items[1].line == 1
    end
end

@testset "discover_testsets: multiple @testsets in one file" begin
    mktempdir() do dir
        path = joinpath(dir, "test_multi.jl")
        write(path, """
        @testset "First" begin
            @test 1 == 1
        end

        @testset "Second" begin
            @test 2 == 2
        end
        """)
        items = Testimonial.discover_testsets([dir])
        @test length(items) == 2
        @test items[1].name == "First"
        @test items[2].name == "Second"
        @test items[1].line == 1
        @test items[2].line == 5
    end
end

@testset "discover_testsets: recursive into subdirectories" begin
    mktempdir() do dir
        top = joinpath(dir, "top.jl")
        write(top, """@testset "Top" begin @test 1 == 1 end""")

        sub = joinpath(dir, "sub")
        mkpath(sub)
        nested = joinpath(sub, "nested.jl")
        write(nested, """@testset "Nested" begin @test 2 == 2 end""")

        items = Testimonial.discover_testsets([dir])
        @test length(items) == 2
        names = sort([item.name for item in items])
        @test names == ["Nested", "Top"]
    end
end

@testset "discover_testsets: empty directory returns empty" begin
    mktempdir() do dir
        @test Testimonial.discover_testsets([dir]) == Testimonial.TestItemRef[]
    end
end

@testset "discover_all_test_blocks: mixed @testitem and @testset" begin
    mktempdir() do dir
        path = joinpath(dir, "test_mixed.jl")
        write(path, """
        @testitem "unit_test" begin
            @test 1 == 1
        end

        @testset "Integration" begin
            @test 2 == 2
        end
        """)
        items = Testimonial.discover_all_test_blocks([dir])
        @test length(items) == 2
        # @testitem comes first, @testset second
        @test items[1].name == "unit_test"
        @test items[2].name == "Integration"
    end
end

@testset "discover_all_test_blocks: file-level fallback for files with no test blocks" begin
    mktempdir() do dir
        # A file with @test but no @testitem or @testset
        path = joinpath(dir, "test_plain.jl")
        write(path, """
        @test 1 == 1
        @test 2 == 2
        """)
        items = Testimonial.discover_all_test_blocks([dir])
        @test length(items) == 1
        @test endswith(items[1].file, "test_plain.jl")
        @test items[1].line == 0  # file-level fallback marker
        @test items[1].name == "test_plain.jl"
    end
end

@testset "discover_all_test_blocks: no fallback for files with @testitem" begin
    mktempdir() do dir
        path = joinpath(dir, "test_item.jl")
        write(path, """
        @testitem "my_test" begin
            @test 1 == 1
        end
        """)
        items = Testimonial.discover_all_test_blocks([dir])
        @test length(items) == 1
        @test items[1].name == "my_test"
        @test items[1].line == 1
    end
end

@testset "discover_all_test_blocks: no fallback for files with @testset" begin
    mktempdir() do dir
        path = joinpath(dir, "test_set.jl")
        write(path, """
        @testset "My Set" begin
            @test 1 == 1
        end
        """)
        items = Testimonial.discover_all_test_blocks([dir])
        @test length(items) == 1
        @test items[1].name == "My Set"
        @test items[1].line == 1
    end
end

@testset "discover_all_test_blocks: fallback only for .jl files in test dirs" begin
    mktempdir() do dir
        # A .jl file with no test blocks (should get fallback)
        path = joinpath(dir, "test_plain.jl")
        write(path, """@test 1 == 1""")

        # A non-.jl file (should be ignored)
        other = joinpath(dir, "notes.txt")
        write(other, "not a test file")

        items = Testimonial.discover_all_test_blocks([dir])
        @test length(items) == 1
        @test endswith(items[1].file, "test_plain.jl")
    end
end