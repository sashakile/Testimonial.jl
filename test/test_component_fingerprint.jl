# Testimonial.jl — Tests for dependency fingerprint computation
#
# Verifies that dependency fingerprints are computed correctly for
# components, including transitive dependencies and content changes.
#
# See testimonial-eub in openspec/changes/add-component-boundary/tasks.md

using Testimonial
using Test
using SHA

# ── compute_dependency_fingerprint ─────────────

@testset "fingerprint: single component, no dependencies" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("src")
            write("src/foo.jl", "module Foo end")
            write("Project.toml", """
name = "MyApp"
version = "1.0.0"
""")

            path_map = Testimonial.component_paths(dir)
            edges = Dict{String, Set{String}}()

            fp = Testimonial.compute_dependency_fingerprint("MyApp", path_map, edges, dir)

            @test fp isa String
            @test !isempty(fp)
            @test length(fp) == 64  # SHA-256 hex
        end
    end
end

@testset "fingerprint: deterministic for same content" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("src")
            write("src/foo.jl", "module Foo end")
            write("Project.toml", "name = \"MyApp\"\nversion = \"1.0.0\"\n")

            path_map = Testimonial.component_paths(dir)
            edges = Dict{String, Set{String}}()

            fp1 = Testimonial.compute_dependency_fingerprint("MyApp", path_map, edges, dir)
            fp2 = Testimonial.compute_dependency_fingerprint("MyApp", path_map, edges, dir)

            @test fp1 == fp2
        end
    end
end

@testset "fingerprint: changes when source content changes" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("src")
            write("src/foo.jl", "module Foo end")
            write("Project.toml", "name = \"MyApp\"\nversion = \"1.0.0\"\n")

            path_map = Testimonial.component_paths(dir)
            edges = Dict{String, Set{String}}()

            fp1 = Testimonial.compute_dependency_fingerprint("MyApp", path_map, edges, dir)

            # Modify source file
            write("src/foo.jl", "module Foo\nfunction bar() end\nend")

            fp2 = Testimonial.compute_dependency_fingerprint("MyApp", path_map, edges, dir)

            @test fp1 != fp2
        end
    end
end

@testset "fingerprint: includes transitive dependencies" begin
    mktempdir() do dir
        cd(dir) do
            # Workspace with LibA and LibB, where LibB depends on LibA
            write("Project.toml", """
name = "Workspace"
version = "1.0.0"
[workspace]
packages = ["pkgs/A", "pkgs/B"]
""")

            for (pkg, name) in [("pkgs/A", "LibA"), ("pkgs/B", "LibB")]
                pkg_dir = joinpath(dir, pkg)
                mkpath(joinpath(pkg_dir, "src"))
                mkpath(joinpath(pkg_dir, "test"))
                write(joinpath(pkg_dir, "Project.toml"), "name = \"$name\"\nversion = \"1.0.0\"\n")
            end

            write("pkgs/A/src/core.jl", "module Core end")
            write("pkgs/B/src/plugin.jl", "module Plugin end")

            path_map = Testimonial.component_paths(dir)
            # LibB depends on LibA
            edges = Dict{String, Set{String}}("LibB" => Set(["LibA"]))

            fp_a = Testimonial.compute_dependency_fingerprint("LibA", path_map, edges, dir)
            fp_b = Testimonial.compute_dependency_fingerprint("LibB", path_map, edges, dir)

            # LibB's fingerprint should include LibA's source files
            @test fp_a != fp_b

            # Modify LibA's source — both fingerprints should change
            write("pkgs/A/src/core.jl", "module Core\nx = 1\nend")
            fp_a2 = Testimonial.compute_dependency_fingerprint("LibA", path_map, edges, dir)
            fp_b2 = Testimonial.compute_dependency_fingerprint("LibB", path_map, edges, dir)

            @test fp_a != fp_a2
            @test fp_b != fp_b2  # LibB's fingerprint also changes because it depends on LibA
        end
    end
end

@testset "fingerprint: no source files" begin
    mktempdir() do dir
        cd(dir) do
            # No src/ directory at all
            write("Project.toml", "name = \"EmptyApp\"\nversion = \"1.0.0\"\n")

            path_map = Testimonial.component_paths(dir)
            edges = Dict{String, Set{String}}()

            fp = Testimonial.compute_dependency_fingerprint("EmptyApp", path_map, edges, dir)

            @test fp isa String
            @test !isempty(fp)
            # Should still include environment fingerprint
        end
    end
end

@testset "fingerprint: different components have different fingerprints" begin
    mktempdir() do dir
        cd(dir) do
            write("Project.toml", """
name = "Workspace"
version = "1.0.0"
[workspace]
packages = ["pkgs/A", "pkgs/B"]
""")

            for (pkg, name) in [("pkgs/A", "LibA"), ("pkgs/B", "LibB")]
                pkg_dir = joinpath(dir, pkg)
                mkpath(joinpath(pkg_dir, "src"))
                mkpath(joinpath(pkg_dir, "test"))
                write(joinpath(pkg_dir, "Project.toml"), "name = \"$name\"\nversion = \"1.0.0\"\n")
            end

            write("pkgs/A/src/a.jl", "module A end")
            write("pkgs/B/src/b.jl", "module B end")

            path_map = Testimonial.component_paths(dir)
            edges = Dict{String, Set{String}}()

            fp_a = Testimonial.compute_dependency_fingerprint("LibA", path_map, edges, dir)
            fp_b = Testimonial.compute_dependency_fingerprint("LibB", path_map, edges, dir)

            @test fp_a != fp_b
        end
    end
end