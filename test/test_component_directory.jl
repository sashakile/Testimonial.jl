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