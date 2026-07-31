# Testimonial.jl — Tests for per-component index directory structure
#
# Verifies the routing file and per-component index path helpers.
#
# See testimonial-3ig in openspec/changes/add-component-boundary/

using Testimonial
using Test

@testset "component_index_dir" begin
    dir = Testimonial.component_index_dir()
    @test dir == ".testimonial/components"
    @test endswith(dir, "components")
end

@testset "component_index_path" begin
    path = Testimonial.component_index_path("MyPkg")
    @test endswith(path, "MyPkg/index.jls")
    @test occursin(".testimonial/components/", path)

    path2 = Testimonial.component_index_path("LibA")
    @test endswith(path2, "LibA/index.jls")
end

@testset "component_index_path with empty name" begin
    path = Testimonial.component_index_path("")
    @test endswith(path, "/index.jls")
end

@testset "save and load routing" begin
    mktempdir() do dir
        Testimonial.save_routing(dir, [:PkgA, :PkgB])
        loaded = Testimonial.load_routing(dir)
        @test loaded == [:PkgA, :PkgB]
    end
end

@testset "load routing returns empty for missing dir" begin
    mktempdir() do dir
        # Don't save anything — no routing file
        loaded = Testimonial.load_routing(dir)
        @test isempty(loaded)
    end
end

@testset "load routing returns empty for empty file" begin
    mktempdir() do dir
        # Write an empty file
        write(joinpath(dir, "index.jls"), "")
        loaded = Testimonial.load_routing(dir)
        @test isempty(loaded)
    end
end

@testset "save and load routing with single component" begin
    mktempdir() do dir
        Testimonial.save_routing(dir, [:LibA])
        loaded = Testimonial.load_routing(dir)
        @test loaded == [:LibA]
    end
end

@testset "save and load routing with empty list" begin
    mktempdir() do dir
        Testimonial.save_routing(dir, Symbol[])
        loaded = Testimonial.load_routing(dir)
        @test isempty(loaded)
    end
end

# ── Unmapped component routing (testimonial-3yem.4) ──

@testset "__unmapped__ items survive component save and load" begin
    mktempdir() do dir
        cd(dir) do
            # Create a test item not under any known component
            ref = Testimonial.TestItemRef(abspath("test/unmapped_test.jl"), 1, "unmapped_item")
            ic = Testimonial.ItemCoverage(ref, [1], Int[], Dict{String, Tuple{Vector{Int}, Vector{Int}}}())

            # Create a component test item
            comp_ref = Testimonial.TestItemRef(abspath("pkgs/MyApp/test/app_test.jl"), 1, "mapped_item")
            comp_ic = Testimonial.ItemCoverage(comp_ref, [1], Int[], Dict{String, Tuple{Vector{Int}, Vector{Int}}}())

            item_map = Dict{Testimonial.TestItemRef, Testimonial.ItemCoverage}(
                ref => ic,
                comp_ref => comp_ic,
            )

            # Create Project.toml with workspace components
            write("Project.toml", """
name = "TestPkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/MyApp"]
""")
            mkpath("pkgs/MyApp")
            write("pkgs/MyApp/Project.toml", """
name = "MyApp"
version = "0.1.0"
""")

            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)
            run(`git add -A`)
            run(`git commit -m init`)

            # Call the internal save function
            parent = Base.parentmodule(Testimonial.IndexBuilder)
            git_sha = String(readchomp(`git rev-parse HEAD`))
            Testimonial.IndexBuilder._save_per_component_indices(
                parent, item_map, dir,
                git_sha,
                "v1.12.0+abc123",
            )

            # Verify the routing file includes __unmapped__
            routing = Testimonial.load_routing(".testimonial")
            @test :__unmapped__ in routing

            # Load through the routing path and verify both items present
            loaded = Testimonial.load_index(".testimonial/index.jls")
            @test loaded !== nothing

            found_names = Set(r.name for (r, _) in loaded.items)
            @test "unmapped_item" in found_names
            @test "mapped_item" in found_names
        end
    end
end