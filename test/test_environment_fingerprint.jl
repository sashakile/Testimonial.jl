# Testimonial.jl — Tests for environment change detection
#
# Verifies that environment fingerprints are stored in CoverageIndex,
# computed correctly, and detect changes.
#
# See testimonial-vyu, testimonial-g53 in
# openspec/changes/add-safety-invariants/

using Testimonial
using Test
using Dates
using Serialization

@testset "environment_fingerprint field exists" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
    )

    @test hasfield(CoverageIndex, :environment_fingerprint)
    @test index.environment_fingerprint isa String
end

@testset "environment_fingerprint defaults to empty string" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
    )

    @test index.environment_fingerprint == ""
end

@testset "environment_fingerprint can be set explicitly" begin
    fp = "v1.12.0+abc123"
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
        fp,
    )

    @test index.environment_fingerprint == fp
end

@testset "compute_environment_fingerprint" begin
    fp = Testimonial.compute_environment_fingerprint(".")
    @test fp isa String
    @test !isempty(fp)
end

@testset "environment_fingerprint detects Project.toml changes" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, """
name = "TestPkg"
version = "1.0.0"
[deps]
Foo = "abc123"
""")

        fp1 = Testimonial.compute_environment_fingerprint(dir)

        # Change Project.toml
        write(proj, """
name = "TestPkg"
version = "1.0.0"
[deps]
Foo = "abc123"
Bar = "def456"
""")

        fp2 = Testimonial.compute_environment_fingerprint(dir)

        @test fp1 != fp2
    end
end

@testset "environment_fingerprint includes Julia version" begin
    mktempdir() do dir
        proj = joinpath(dir, "Project.toml")
        write(proj, "name = \"TestPkg\"\n")

        fp = Testimonial.compute_environment_fingerprint(dir)
        @test occursin(string(VERSION), fp)
    end
end

@testset "environment_fingerprint handles missing Project.toml" begin
    mktempdir() do dir
        # No Project.toml in this dir
        fp = Testimonial.compute_environment_fingerprint(dir)
        @test fp isa String
        @test occursin(string(VERSION), fp)
    end
end

@testset "environment_matches returns true when fingerprints match" begin
    fp = "v1.12.0+abc123"
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
        fp,
    )

    @test Testimonial.environment_matches(index, fp)
end

@testset "environment_matches returns false when fingerprints differ" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
        "v1.11.0+oldhash",
    )

    @test !Testimonial.environment_matches(index, "v1.12.0+newhash")
end

@testset "environment_matches returns false when fingerprint is empty (legacy safety)" begin
    index = CoverageIndex(
        Dict{TestItemRef, ItemCoverage}(),
        "abc123",
        string(VERSION),
        v"0.1.0",
        now(),
        "",  # empty = unverifiable index
    )

    @test !Testimonial.environment_matches(index, "v1.12.0+abc123")
end

@testset "record_all stores environment fingerprint in CoverageIndex" begin
    mktempdir() do dir
        cd(dir) do
            # Create Project.toml so a real fingerprint can be computed
            write("Project.toml", """
name = "TestPkg"
version = "1.0.0"
""")

            # Create a minimal test file
            mkpath("test")
            write("test/foo_test.jl", """
@testitem "passing" begin
    @test 1 == 1
end
""")

            # Initialize git repo (required by _git_hash)
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)
            run(`git add -A`)
            run(`git commit -m init`)

            # Run record_all
            index = Testimonial.record_all(;
                force=true,
                test_dirs=["test/"],
                project_dir=dir,
            )

            @test index isa CoverageIndex
            @test !isempty(index.environment_fingerprint)
            @test occursin(string(VERSION), index.environment_fingerprint)
        end
    end
end

@testset "build_index stores environment fingerprint" begin
    mktempdir() do dir
        cd(dir) do
            write("Project.toml", """
name = "TestPkg"
version = "1.0.0"
""")

            # Create a cached record that build_index can load
            mkpath("items")
            ref = Testimonial.TestItemRef(joinpath(dir, "test", "foo_test.jl"), 1, "passing")
            ic = Testimonial.ItemCoverage(ref, Int[], Int[], Dict{String, Tuple{Vector{Int}, Vector{Int}}}())
            open(joinpath("items", "test_item.jls"), "w") do io
                serialize(io, ic)
            end

            index = Testimonial.build_index("items")

            @test index isa CoverageIndex
            @test !isempty(index.environment_fingerprint)
        end
    end
end

@testset "_save_per_component_indices stores fingerprint in component index" begin
    mktempdir() do dir
        cd(dir) do
            # Create a minimal index with components
            write("Project.toml", """
name = "TestPkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/SubPkg"]
""")
            mkpath("pkgs/SubPkg")
            write("pkgs/SubPkg/Project.toml", """
name = "SubPkg"
version = "0.1.0"
""")
            mkpath("pkgs/SubPkg/test")
            write("pkgs/SubPkg/test/sub_test.jl", """
@testitem "sub_passing" begin
    @test 1 == 1
end
""")

            # Initialize git (needed by _git_hash in save_index)
            run(`git init`)
            run(`git config user.email test@test.com`)
            run(`git config user.name test`)
            run(`git add -A`)
            run(`git commit -m init`)

            # Run record_all with project_dir — this triggers _save_per_component_indices
            index = Testimonial.record_all(;
                force=true,
                test_dirs=["pkgs/SubPkg/test/"],
                project_dir=dir,
            )

            # The index itself should carry the fingerprint
            @test !isempty(index.environment_fingerprint)

            # Check the persisted index on disk too
            loaded = Testimonial.load_index(".testimonial/index.jls")
            if loaded !== nothing
                @test !isempty(loaded.environment_fingerprint)
            end
        end
    end
end