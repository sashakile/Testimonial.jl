# Testimonial.jl — Unit test for record_item with MockRunner
#
# Verifies that record_item constructs the correct subprocess command
# without actually spawning any processes. The MockRunner captures the
# command for inspection.
#
# See REC-011 in openspec/changes/implement-coverage-layer/specs/recording/spec.md

using Testimonial
using Test

# ── Tests ──────────────────────────────────────

@testset "MockRunner captures command" begin
    runner = MockRunner()
    ref = Testimonial.TestItemRef("test/foo.jl", 10, "test_foo")

    result = Testimonial.record_item(runner, ref)

    @test result isa Testimonial.ItemCoverage
    @test !isempty(runner.captured_cmd)
    @test occursin("julia", runner.captured_cmd[1])
    @test occursin("--code-coverage", join(runner.captured_cmd, " "))
end

@testset "MockRunner captures env vars" begin
    runner = MockRunner()
    ref = Testimonial.TestItemRef("test/bar.jl", 5, "test_bar")

    Testimonial.record_item(runner, ref)

    @test haskey(runner.captured_env, "TESTIMONIAL_FILE")
    @test haskey(runner.captured_env, "TESTIMONIAL_ITEM")
    @test runner.captured_env["TESTIMONIAL_FILE"] == "test/bar.jl"
    @test runner.captured_env["TESTIMONIAL_ITEM"] == "test_bar"
end

@testset "MockRunner does not spawn processes" begin
    runner = MockRunner()
    ref = Testimonial.TestItemRef("test/baz.jl", 15, "test_baz")

    # Just verify the method returns without error — no subprocess is spawned
    result = Testimonial.record_item(runner, ref)
    @test result isa Testimonial.ItemCoverage
end

# ── record_file (file-level) ────────────────

@testset "record_file captures TESTIMONIAL_RUN_ALL env" begin
    runner = MockRunner()
    test_file = "test/foo_test.jl"

    result = Testimonial.record_file(runner, test_file)

    @test result isa Testimonial.ItemCoverage
    @test haskey(runner.captured_env, "TESTIMONIAL_RUN_ALL")
    @test runner.captured_env["TESTIMONIAL_RUN_ALL"] == "true"
    @test haskey(runner.captured_env, "TESTIMONIAL_FILE")
    @test runner.captured_env["TESTIMONIAL_FILE"] == test_file
    @test !haskey(runner.captured_env, "TESTIMONIAL_ITEM")
    @test !haskey(runner.captured_env, "TESTIMONIAL_ITEMS")
end

@testset "record_file returns file-level ref" begin
    runner = MockRunner()
    test_file = "test/bar_test.jl"

    result = Testimonial.record_file(runner, test_file)

    @test result.item.file == test_file
    @test result.item.line == 0  # file-level: no specific line
    @test result.item.name == "bar_test.jl"  # basename
end

@testset "record_file returns nothing for missing file" begin
    # Use SubprocessRunner which calls the real implementation
    runner = Testimonial.SubprocessRunner()

    result = Testimonial.record_file(runner, "/nonexistent/file.jl")
    @test result === nothing
end