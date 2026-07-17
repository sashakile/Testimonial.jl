# Quick test runner — excludes slow subprocess tests (test_protocol.jl, test_subprocess_record.jl, test_runner.jl)
# Use via: just test-quick

using Testimonial, Test, Dates

include("helpers.jl")

@testset "Quick tests" begin
    include("test_types.jl")
    include("test_persistence.jl")
    include("test_astparser.jl")
    include("test_gitdiff.jl")
    include("test_command.jl")
    include("test_runner_types.jl")
    include("test_indexbuilder.jl")
    include("test_mockrunner.jl")
    include("test_cov_sidecar.jl")
    include("test_timeout.jl")
    include("test_changed_detection.jl")
    include("test_query.jl")
    include("test_driver.jl")
    include("test_record_all.jl")
    include("test_build_index_integration.jl")
    include("test_cli.jl")
end
