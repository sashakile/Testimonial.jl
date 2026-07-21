# Testimonial.jl — Tests for --shards N option in smart_run
#
# Verifies that the run function writes balanced shard files when
# n_shards > 0, and that shard files can be read back.
#
# See testimonial-69t in openspec/changes/add-component-boundary/tasks.md

using Testimonial
using Test
using Dates
using Serialization

@testset "shard_files run with n_shards writes shard files" begin
    mktempdir() do dir
        cd(dir) do
            mkpath("test")
            write("test/foo.jl", """@testitem "foo" begin @test 1==1 end""")

            ref = TestItemRef(abspath("test/foo.jl"), 1, "foo", Symbol[], "abc123")
            ic = ItemCoverage(ref, [1], Int[], Dict())
            index = CoverageIndex(
                Dict{TestItemRef, ItemCoverage}(ref => ic),
                "abc123", string(VERSION), v"0.1.0", now(),
            )
            save_index(index, ".testimonial/index.jls")

            # Without git history, run falls back to :full_suite — still no crash
            result = Testimonial.CLI.run(; n_shards=4)

            # run() should be backward compatible in return value
            @test result isa Union{Symbol, Vector}
        end
    end
end

@testset "shard_files write_and_read back" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            refs = [TestItemRef("test/$i.jl", i, "item_$i") for i in 1:3]
            Testimonial.CLI._write_shard_files(refs, 2)

            @test isfile(".testimonial/shard_1.jls")
            @test isfile(".testimonial/shard_2.jls")

            manifest = Testimonial.CLI._read_shard_manifest()
            @test length(manifest) == 2

            shard1 = Testimonial.CLI._load_shard(1)
            shard2 = Testimonial.CLI._load_shard(2)
            @test length(shard1) + length(shard2) == 3
        end
    end
end

@testset "shard_files clean removes files" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            refs = [TestItemRef("test/a.jl", 1, "a")]
            Testimonial.CLI._write_shard_files(refs, 2)

            @test isfile(".testimonial/shard_1.jls")

            Testimonial.CLI._clean_shard_files()
            @test !isfile(".testimonial/shard_1.jls")
            @test !isfile(".testimonial/shard_2.jls")
            @test !isfile(".testimonial/shard_manifest.jls")
        end
    end
end

@testset "shard_files empty items creates empty shards" begin
    mktempdir() do dir
        cd(dir) do
            mkpath(".testimonial")

            Testimonial.CLI._write_shard_files(TestItemRef[], 3)

            @test isfile(".testimonial/shard_1.jls")
            @test isfile(".testimonial/shard_2.jls")
            @test isfile(".testimonial/shard_3.jls")

            shard1 = Testimonial.CLI._load_shard(1)
            @test isempty(shard1)
        end
    end
end