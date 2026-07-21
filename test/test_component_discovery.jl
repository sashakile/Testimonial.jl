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