# Testimonial.jl — Tests for must-run config parsing
#
# Verifies that must_run rules can be parsed from a TOML config section.
#
# See testimonial-cvn in openspec/changes/add-safety-invariants/

using Testimonial
using Test

@testset "parse_must_run_rules from Dict" begin
    config = Dict(
        "must_run" => Dict(
            "rules" => [
                Dict("changed_glob" => "src/critical/*.jl", "test_tag" => "critical"),
                Dict("changed_glob" => "config/*.toml", "test_tag" => "config"),
            ]
        )
    )

    rules = Testimonial.parse_must_run_rules(config)

    @test length(rules) == 2
    @test rules[1].changed_glob == "src/critical/*.jl"
    @test rules[1].test_tag == :critical
    @test rules[2].changed_glob == "config/*.toml"
    @test rules[2].test_tag == :config
end

@testset "parse_must_run_rules handles empty config" begin
    rules = Testimonial.parse_must_run_rules(Dict())
    @test isempty(rules)
end

@testset "parse_must_run_rules handles missing must_run section" begin
    config = Dict("other" => "value")
    rules = Testimonial.parse_must_run_rules(config)
    @test isempty(rules)
end

@testset "parse_must_run_rules handles empty rules list" begin
    config = Dict("must_run" => Dict("rules" => []))
    rules = Testimonial.parse_must_run_rules(config)
    @test isempty(rules)
end

@testset "parse_must_run_rules converts string tag to Symbol" begin
    config = Dict(
        "must_run" => Dict(
            "rules" => [
                Dict("changed_glob" => "src/*.jl", "test_tag" => "critical"),
            ]
        )
    )

    rules = Testimonial.parse_must_run_rules(config)
    @test length(rules) == 1
    @test rules[1].test_tag == :critical
end