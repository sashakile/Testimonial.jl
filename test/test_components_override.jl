# Testimonial.jl — Tests for components override in Testimonial.toml
#
# Verifies that the [components] section in Testimonial.toml can override
# auto-detected component names and paths.
#
# See testimonial-79i in openspec/changes/add-component-boundary/tasks.md

using Testimonial
using Test
using Dates

# ── read_testimonial_config ────────────────────

@testset "toml config: reads components override" begin
    mktempdir() do dir
        cd(dir) do
            write("Testimonial.toml", """
[components]
PkgA = "pkgs/PkgA"
PkgB = "pkgs/PkgB"
""")

            config = Testimonial.read_testimonial_config(dir)
            @test config isa Dict
            @test haskey(config, "components")
            @test config["components"]["PkgA"] == "pkgs/PkgA"
            @test config["components"]["PkgB"] == "pkgs/PkgB"
        end
    end
end

@testset "toml config: returns empty dict when no file exists" begin
    mktempdir() do dir
        cd(dir) do
            config = Testimonial.read_testimonial_config(dir)
            @test isempty(config)
        end
    end
end

# ── parse_components_override ─────────────────

@testset "parse override: returns path map from TOML config" begin
    config = Dict{String, Any}(
        "components" => Dict{String, Any}(
            "PkgA" => "pkgs/PkgA",
            "PkgB" => "pkgs/PkgB",
        ),
    )

    path_map = Testimonial.parse_components_override(config)
    @test haskey(path_map, :PkgA)
    @test haskey(path_map, :PkgB)
    @test path_map[:PkgA] == "pkgs/PkgA"
    @test path_map[:PkgB] == "pkgs/PkgB"
end

@testset "parse override: returns empty dict when no components section" begin
    config = Dict{String, Any}()
    path_map = Testimonial.parse_components_override(config)
    @test isempty(path_map)
end

@testset "parse override: returns empty dict for empty components section" begin
    config = Dict{String, Any}("components" => Dict{String, Any}())
    path_map = Testimonial.parse_components_override(config)
    @test isempty(path_map)
end

# ── component_paths with override ─────────────

@testset "component_paths: uses override when Testimonial.toml has [components]" begin
    mktempdir() do dir
        cd(dir) do
            # Create a Project.toml with a workspace (would normally be used)
            write("Project.toml", """
name = "WS"
version = "1.0.0"
[workspace]
packages = ["pkgs/LibA"]
""")

            for (pkg, name) in [("pkgs/LibA", "LibA")]
                pkg_dir = joinpath(dir, pkg)
                mkpath(pkg_dir)
                write(joinpath(pkg_dir, "Project.toml"), "name = \"$name\"\nversion = \"1.0.0\"\n")
            end

            # Create Testimonial.toml with override
            write("Testimonial.toml", """
[components]
CustomPkg = "pkgs/CustomPkg"
""")

            mkpath("pkgs/CustomPkg")
            write("pkgs/CustomPkg/Project.toml", "name = \"CustomPkg\"\nversion = \"1.0.0\"\n")

            path_map = Testimonial.component_paths(dir)
            @test haskey(path_map, :CustomPkg)
            @test !haskey(path_map, :LibA)  # Should NOT find LibA from workspace
        end
    end
end

@testset "component_paths: falls back to workspace discovery without override" begin
    mktempdir() do dir
        cd(dir) do
            # No Testimonial.toml
            write("Project.toml", "name = \"MyApp\"\nversion = \"1.0.0\"\n")

            path_map = Testimonial.component_paths(dir)
            @test haskey(path_map, :MyApp)
        end
    end
end

@testset "component_of: works with override paths" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("pkgs/MyPkg/src")
            write("pkgs/MyPkg/src/foo.jl", "module Foo end")

            path_map = Dict{Symbol, String}(:MyPkg => joinpath(dir, "pkgs/MyPkg"))

            # Test file inside the component
            comp = Testimonial.component_of(
                joinpath(dir, "pkgs/MyPkg/src/foo.jl"),
                path_map,
            )
            @test comp == :MyPkg

            # Test file outside the component
            comp = Testimonial.component_of(
                joinpath(dir, "other/file.jl"),
                path_map,
            )
            @test comp === nothing
        end
    end
end