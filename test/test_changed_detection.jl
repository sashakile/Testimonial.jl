# Testimonial.jl — Tests for test-file-changed detection
#
# Verifies that select_changed_items correctly identifies @testitems
# in files that have changed, filtering only files under test directories.
#
# See task testimonial-7pe in
# openspec/changes/implement-coverage-layer/tasks.md

using Testimonial
using Test

# ── select_changed_items ──────────────────────

@testset "select_changed_items finds items in changed test files" begin
    mktempdir() do dir
        test_file = joinpath(dir, "foo_test.jl")
        write(test_file, """
        @testitem "item_a" begin
            @test 1 == 1
        end
        @testitem "item_b" begin
            @test 2 == 2
        end
        """)

        # Add a non-test file
        other_file = joinpath(dir, "other.jl")
        write(other_file, "x = 1")

        result = Testimonial.select_changed_items(
            [test_file, other_file],
            [dir]
        )

        @test length(result) == 2
        names = sort([r.name for r in result])
        @test names == ["item_a", "item_b"]
        @test all(r -> r.file == test_file, result)
    end
end

@testset "select_changed_items ignores files outside test dirs" begin
    mktempdir() do dir
        test_dir = joinpath(dir, "test")
        mkpath(test_dir)
        test_file = joinpath(test_dir, "bar_test.jl")
        write(test_file, """
        @testitem "item" begin
            @test 1 == 1
        end
        """)

        src_file = joinpath(dir, "src", "foo.jl")
        mkpath(joinpath(dir, "src"))
        write(src_file, "module Foo; end")

        result = Testimonial.select_changed_items(
            [src_file, test_file],
            [test_dir]
        )

        @test length(result) == 1
        @test result[1].name == "item"
    end
end

@testset "select_changed_items returns empty for no changed test files" begin
    mktempdir() do dir
        test_dir = joinpath(dir, "test")
        mkpath(test_dir)

        src_file = joinpath(dir, "src", "foo.jl")
        mkpath(joinpath(dir, "src"))
        write(src_file, "module Foo; end")

        result = Testimonial.select_changed_items(
            [src_file],
            [test_dir]
        )

        @test isempty(result)
    end
end

@testset "select_changed_items handles empty changed_files" begin
    result = Testimonial.select_changed_items(String[], ["test/"])
    @test isempty(result)
end

@testset "select_changed_items deduplicates repeated file paths" begin
    mktempdir() do dir
        test_file = joinpath(dir, "dedup_test.jl")
        write(test_file, """
        @testitem "only" begin
            @test 1 == 1
        end
        """)

        # Same file listed twice
        result = Testimonial.select_changed_items(
            [test_file, test_file, test_file],
            [dir]
        )

        @test length(result) == 1
        @test result[1].name == "only"
    end
end

@testset "select_changed_items handles files with no @testitem blocks" begin
    mktempdir() do dir
        test_file = joinpath(dir, "empty_test.jl")
        write(test_file, "x = 1  # no test items")

        result = Testimonial.select_changed_items(
            [test_file],
            [dir]
        )

        @test isempty(result)
    end
end

@testset "select_changed_items works with multiple test directories" begin
    mktempdir() do dir
        dir_a = joinpath(dir, "a")
        mkpath(dir_a)
        file_a = joinpath(dir_a, "a_test.jl")
        write(file_a, """
        @testitem "from_a" begin
            @test 1 == 1
        end
        """)

        dir_b = joinpath(dir, "b")
        mkpath(dir_b)
        file_b = joinpath(dir_b, "b_test.jl")
        write(file_b, """
        @testitem "from_b" begin
            @test 2 == 2
        end
        """)

        result = Testimonial.select_changed_items(
            [file_a, file_b],
            [dir_a, dir_b]
        )

        @test length(result) == 2
        names = sort([r.name for r in result])
        @test names == ["from_a", "from_b"]
    end
end

# ── _discover_in_file ─────────────────────────

@testset "_discover_in_file finds test items in a file" begin
    mktempdir() do dir
        test_file = joinpath(dir, "discover_test.jl")
        write(test_file, """
        @testitem "first" begin
            @test 1 == 1
        end
        @testitem "second" begin
            @test 2 == 2
        end
        """)

        items = Testimonial._discover_in_file(test_file)

        @test length(items) == 2
        @test items[1].name == "first"
        @test items[2].name == "second"
        @test all(i -> i.file == test_file, items)
    end
end

@testset "_discover_in_file returns empty for nonexistent file" begin
    items = Testimonial._discover_in_file("/nonexistent/path.jl")
    @test isempty(items)
end

@testset "_discover_in_file returns empty for file with no test items" begin
    mktempdir() do dir
        test_file = joinpath(dir, "plain.jl")
        write(test_file, "module Plain; end")

        items = Testimonial._discover_in_file(test_file)
        @test isempty(items)
    end
end