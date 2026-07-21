# Testimonial.jl — Tests for index migration from flat to per-component
#
# Verifies that migrate_index correctly converts old flat CoverageIndex
# to per-component layout with routing file.
#
# See testimonial-h1o in openspec/changes/add-component-boundary/

using Testimonial
using Test
using Serialization
using Dates

@testset "migrate_index converts flat index to per-component" begin
    mktempdir() do dir
        cd(dir) do
            # Create a flat index (old format) as it would appear after record_all
            ref_a1 = TestItemRef("pkgs/PkgA/test/a1.jl", 10, "test_a1")
            ref_a2 = TestItemRef("pkgs/PkgA/test/a2.jl", 5, "test_a2")
            ref_b = TestItemRef("pkgs/PkgB/test/b.jl", 10, "test_b")

            ic_a1 = ItemCoverage(ref_a1, [1, 2], Int[], Dict())
            ic_a2 = ItemCoverage(ref_a2, [3, 4], Int[], Dict())
            ic_b = ItemCoverage(ref_b, [5, 6], Int[], Dict())

            flat_index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref_a1 => ic_a1, ref_a2 => ic_a2, ref_b => ic_b),
                "abc123", string(VERSION), v"0.1.0", now()
            )
            save_index(flat_index, ".testimonial/index.jls")

            # Also need the project structure for component discovery
            mkpath("pkgs/PkgA/test")
            mkpath("pkgs/PkgB/test")
            write("Project.toml", """
name = "WorkspacePkg"
version = "1.0.0"

[workspace]
packages = ["pkgs/PkgA", "pkgs/PkgB"]
""")
            for (pkg, name) in [("pkgs/PkgA", "PkgA"), ("pkgs/PkgB", "PkgB")]
                write(joinpath(pkg, "Project.toml"), """
name = "$name"
version = "1.0.0"
""")
            end

            # Run migration
            Testimonial.migrate_index(".testimonial", dir)

            # After migration, load_index should return per-component merged index
            loaded = load_index(".testimonial/index.jls")
            @test loaded isa CoverageIndex
            @test length(loaded.items) == 3

            # Per-component files should exist
            @test isfile(Testimonial.component_index_path("PkgA"))
            @test isfile(Testimonial.component_index_path("PkgB"))

            # Each component should have the right items
            pkg_a = Testimonial.load_index(Testimonial.component_index_path("PkgA"))
            @test length(pkg_a.items) == 2
            pkg_b = Testimonial.load_index(Testimonial.component_index_path("PkgB"))
            @test length(pkg_b.items) == 1

            # Routing file should list both
            routing = Testimonial.load_routing(".testimonial")
            @test sort(routing) == [:PkgA, :PkgB]
        end
    end
end

@testset "migrate_index handles single-package project" begin
    mktempdir() do dir
        cd(dir) do
            ref = TestItemRef("test/foo.jl", 10, "test_foo")
            ic = ItemCoverage(ref, [1, 2], Int[], Dict())
            flat_index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123", string(VERSION), v"0.1.0", now()
            )
            save_index(flat_index, ".testimonial/index.jls")

            write("Project.toml", """
name = "MyApp"
version = "1.0.0"
""")

            Testimonial.migrate_index(".testimonial", dir)

            loaded = load_index(".testimonial/index.jls")
            @test loaded isa CoverageIndex
            @test length(loaded.items) == 1

            @test isfile(Testimonial.component_index_path("MyApp"))
            routing = Testimonial.load_routing(".testimonial")
            @test routing == [:MyApp]
        end
    end
end

@testset "migrate_index is idempotent" begin
    mktempdir() do dir
        cd(dir) do
            # Already migrated — routing file exists
            Testimonial.save_routing(".testimonial", [:ExistingPkg])

            # Running migration again should not error
            Testimonial.migrate_index(".testimonial", dir)

            # Should still have routing file
            routing = Testimonial.load_routing(".testimonial")
            @test routing == [:ExistingPkg]
        end
    end
end

@testset "migrate_index handles missing Project.toml" begin
    mktempdir() do dir
        cd(dir) do
            ref = TestItemRef("test/foo.jl", 10, "test_foo")
            ic = ItemCoverage(ref, [1, 2], Int[], Dict())
            flat_index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123", string(VERSION), v"0.1.0", now()
            )
            save_index(flat_index, ".testimonial/index.jls")

            # No Project.toml — migration should still work (no components)
            Testimonial.migrate_index(".testimonial", dir)

            # After migration with no project, routing should be empty
            # and items should go to __unmapped__
            @test isfile(".testimonial/index.jls")
        end
    end
end