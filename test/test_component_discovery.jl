# Testimonial.jl — Tests for component discovery from workspace Project.toml
#
# Verifies that components are discovered by parsing the workspace
# Project.toml [sources] section.
#
# See testimonial-99q in openspec/changes/add-component-boundary/

using Testimonial
using Test

@testset "discover_components from workspace Project.toml" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, """
name = "WorkspacePkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/PkgA", "pkgs/PkgB"]
""")

        # Create sub-package Project.toml files
        for (pkg, name) in [("pkgs/PkgA", "PkgA"), ("pkgs/PkgB", "PkgB")]
            pkg_dir = joinpath(dir, pkg)
            mkpath(pkg_dir)
            write(joinpath(pkg_dir, "Project.toml"), """
name = "$name"
version = "1.0.0"
""")
        end

        components = Testimonial.discover_components(dir)
        @test :PkgA in components
        @test :PkgB in components
        @test length(components) == 2
    end
end

@testset "discover_components without workspace section" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, """
name = "SimplePkg"
version = "1.0.0"
""")

        components = Testimonial.discover_components(dir)
        @test length(components) == 1
        @test :SimplePkg in components
    end
end

@testset "discover_components without Project.toml" begin
    mktempdir() do dir
        components = Testimonial.discover_components(dir)
        @test isempty(components)
    end
end

@testset "discover_components with empty workspace" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, """
name = "EmptyPkg"
version = "1.0.0"

[workspace]
packages = []
""")

        components = Testimonial.discover_components(dir)
        @test length(components) == 1
        @test :EmptyPkg in components
    end
end

@testset "component_of maps test file to component" begin
    components = [:PkgA, :PkgB]
    test_file = "/workspace/pkgs/PkgA/test/foo_test.jl"
    result = Testimonial.component_of(test_file, components)
    @test result == :PkgA
end

@testset "component_of returns nothing for unknown file" begin
    components = [:PkgA]
    test_file = "/workspace/pkgs/Unknown/test/foo_test.jl"
    result = Testimonial.component_of(test_file, components)
    @test result === nothing
end

@testset "component_of maps file using workspace path (not just name match)" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, """
name = "WorkspacePkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/a", "pkgs/b"]
""")

        for (pkg, name) in [("pkgs/a", "PkgA"), ("pkgs/b", "PkgB")]
            pkg_dir = joinpath(dir, pkg)
            mkpath(pkg_dir)
            write(joinpath(pkg_dir, "Project.toml"), """
name = "$name"
version = "1.0.0"
""")
        end

        path_map = Testimonial.component_paths(dir)
        @test path_map[:PkgA] == joinpath(dir, "pkgs/a")
        @test path_map[:PkgB] == joinpath(dir, "pkgs/b")
        @test length(path_map) == 2

        # Map test files using the path map, not just name matching
        test_a = joinpath(dir, "pkgs/a/test/foo_test.jl")
        test_b = joinpath(dir, "pkgs/b/test/bar_test.jl")
        @test Testimonial.component_of(test_a, path_map) == :PkgA
        @test Testimonial.component_of(test_b, path_map) == :PkgB
    end
end

@testset "component_of returns nothing for unknown file via path map" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, """
name = "WorkspacePkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/PkgA"]
""")

        pkg_dir = joinpath(dir, "pkgs/PkgA")
        mkpath(pkg_dir)
        write(joinpath(pkg_dir, "Project.toml"), """
name = "PkgA"
version = "1.0.0"
""")

        path_map = Testimonial.component_paths(dir)
        test_file = joinpath(dir, "pkgs/Unknown/test/foo_test.jl")
        @test Testimonial.component_of(test_file, path_map) === nothing
    end
end

@testset "component_of uses path map for non-matching names" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, """
name = "WorkspacePkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/a", "pkgs/b"]
""")

        for (pkg, name) in [("pkgs/a", "PkgA"), ("pkgs/b", "PkgB")]
            pkg_dir = joinpath(dir, pkg)
            mkpath(pkg_dir)
            write(joinpath(pkg_dir, "Project.toml"), """
name = "$name"
version = "1.0.0"
""")
        end

        path_map = Testimonial.component_paths(dir)

        # The pure name-based component_of would return nothing here
        # because "PkgA" doesn't appear in the path "pkgs/a/test/foo_test.jl"
        test_file = joinpath(dir, "pkgs/a/test/foo_test.jl")
        @test Testimonial.component_of(test_file, [:PkgA, :PkgB]) === nothing

        # But the path-map based version should find it
        @test Testimonial.component_of(test_file, path_map) == :PkgA
    end
end