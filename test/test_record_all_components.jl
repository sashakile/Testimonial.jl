# Testimonial.jl — Tests for per-component index persistence in record_all
#
# Verifies that record_all saves per-component CoverageIndex objects
# under .testimonial/components/<name>/index.jls and writes a routing file.
#
# See testimonial-3ok in openspec/changes/add-component-boundary/

using Testimonial
using Test
using Serialization

include("helpers.jl")

"""Create a workspace project with two component test dirs."""
function create_workspace_project(dir::String)
    # Root Project.toml with workspace
    write(joinpath(dir, "Project.toml"), """
name = "WorkspacePkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/PkgA", "pkgs/PkgB"]
""")

    # PkgA with Project.toml and test dir
    pkg_a_dir = joinpath(dir, "pkgs", "PkgA")
    mkpath(joinpath(pkg_a_dir, "test"))
    write(joinpath(pkg_a_dir, "Project.toml"), """
name = "PkgA"
version = "1.0.0"
""")
    write(joinpath(pkg_a_dir, "test", "a_test.jl"), """
@testitem "test_a1" begin @test 1 == 1 end
@testitem "test_a2" begin @test 2 == 2 end
""")

    # PkgB with Project.toml and test dir
    pkg_b_dir = joinpath(dir, "pkgs", "PkgB")
    mkpath(joinpath(pkg_b_dir, "test"))
    write(joinpath(pkg_b_dir, "Project.toml"), """
name = "PkgB"
version = "1.0.0"
""")
    write(joinpath(pkg_b_dir, "test", "b_test.jl"), """
@testitem "test_b1" begin @test 3 == 3 end
""")

    return dir
end

@testset "record_all saves per-component indices" begin
    mktempdir() do dir
        cd(dir) do
            create_workspace_project(dir)

            # Discover all test items
            test_dirs = [
                joinpath(dir, "pkgs", "PkgA", "test"),
                joinpath(dir, "pkgs", "PkgB", "test"),
            ]
            items = Testimonial.discover_testitems(test_dirs)
            @test length(items) == 3

            # Record all with component grouping
            runner = MockRunner()
            index = record_all(items, runner; force=true, project_dir=dir)

            # Should still return a flat CoverageIndex with all items
            @test index isa CoverageIndex
            @test length(index.items) == 3

            # Per-component index for PkgA should exist
            pkg_a_path = Testimonial.component_index_path("PkgA")
            @test isfile(pkg_a_path)

            pkg_a_index = Testimonial.load_index(pkg_a_path)
            @test pkg_a_index isa CoverageIndex
            @test length(pkg_a_index.items) == 2
            names_a = sort([ic.item.name for (_, ic) in pkg_a_index.items])
            @test names_a == ["test_a1", "test_a2"]

            # Per-component index for PkgB should exist
            pkg_b_path = Testimonial.component_index_path("PkgB")
            @test isfile(pkg_b_path)

            pkg_b_index = Testimonial.load_index(pkg_b_path)
            @test pkg_b_index isa CoverageIndex
            @test length(pkg_b_index.items) == 1
            names_b = [ic.item.name for (_, ic) in pkg_b_index.items]
            @test names_b == ["test_b1"]

            # Routing file should list both components
            routing = Testimonial.load_routing(".testimonial")
            @test :PkgA in routing
            @test :PkgB in routing
            @test length(routing) == 2
        end
    end
end

@testset "record_all without project_dir uses default (no component grouping)" begin
    mktempdir() do dir
        cd(dir) do
            # Single project, no workspace
            write(joinpath(dir, "Project.toml"), """
name = "SimplePkg"
version = "1.0.0"
""")
            test_dir = joinpath(dir, "test")
            mkpath(test_dir)
            write(joinpath(test_dir, "foo_test.jl"), """
@testitem "test_x" begin @test 1 == 1 end
""")

            items = Testimonial.discover_testitems([test_dir])
            runner = MockRunner()
            index = record_all(items, runner; force=true)

            # No component indices should be written
            @test !isdir(".testimonial/components")
        end
    end
end

@testset "record_all saves components with non-matching names" begin
    mktempdir() do dir
        cd(dir) do
            # Workspace where path ≠ component name
            write(joinpath(dir, "Project.toml"), """
name = "WorkspacePkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/a", "pkgs/b"]
""")

            for (pkg, name) in [("pkgs/a", "PkgA"), ("pkgs/b", "PkgB")]
                pkg_dir = joinpath(dir, pkg)
                mkpath(joinpath(pkg_dir, "test"))
                write(joinpath(pkg_dir, "Project.toml"), """
name = "$name"
version = "1.0.0"
""")
                write(joinpath(pkg_dir, "test", "$(name)_test.jl"), """
@testitem "test_$(name)" begin @test 1 == 1 end
""")
            end

            test_dirs = [joinpath(dir, "pkgs", "a", "test"), joinpath(dir, "pkgs", "b", "test")]
            items = Testimonial.discover_testitems(test_dirs)
            runner = MockRunner()
            index = record_all(items, runner; force=true, project_dir=dir)

            # Should resolve via path_map, not name matching
            pkg_a_path = Testimonial.component_index_path("PkgA")
            @test isfile(pkg_a_path)
            pkg_a_index = Testimonial.load_index(pkg_a_path)
            @test length(pkg_a_index.items) == 1
        end
    end
end

@testset "record_all with single project saves one component" begin
    mktempdir() do dir
        cd(dir) do
            # Single package (no workspace detected)
            write(joinpath(dir, "Project.toml"), """
name = "MyApp"
version = "1.0.0"
""")
            test_dir = joinpath(dir, "test")
            mkpath(test_dir)
            write(joinpath(test_dir, "app_test.jl"), """
@testitem "test_app" begin @test 1 == 1 end
""")

            items = Testimonial.discover_testitems([test_dir])
            runner = MockRunner()
            index = record_all(items, runner; force=true, project_dir=dir)

            # Component path for MyApp should exist
            myapp_path = Testimonial.component_index_path("MyApp")
            @test isfile(myapp_path)
            myapp_index = Testimonial.load_index(myapp_path)
            @test length(myapp_index.items) == 1

            # Routing should have one component
            routing = Testimonial.load_routing(".testimonial")
            @test routing == [:MyApp]
        end
    end
end