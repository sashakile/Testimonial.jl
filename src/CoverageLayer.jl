# Coverage recording layer — records coverage for individual @testitems.
#
# Runs each @testitem in an isolated subprocess and parses the resulting
# .jl.cov sidecar files to attribute covered lines back to the item.
#
# See PROTO-004 in openspec/changes/implement-coverage-layer/specs/protocol-adapter/spec.md

module CoverageLayer

export record_item, build_driver_command

"""
    build_driver_command(test_file::String, item_name::String; runner_dir::AbstractString="scripts/TestimonialRunner") -> Tuple{Vector{String}, Dict{String, String}}

Build the subprocess command and environment for recording a single @testitem.

Returns a tuple `(cmd, env)` where `cmd` is the argument vector for the Julia
subprocess and `env` is a dict of environment variables to set.

Generated command:
    julia --code-coverage=user --project=<runner_dir> <runner_dir>/driver.jl

Environment:
    TESTIMONIAL_FILE=<test_file>
    TESTIMONIAL_ITEM=<item_name>
"""
function build_driver_command(
    test_file::AbstractString,
    item_name::AbstractString;
    runner_dir::AbstractString="scripts/TestimonialRunner"
)::Tuple{Vector{String}, Dict{String, String}}
    driver_path = joinpath(runner_dir, "driver.jl")
    cmd = [
        "julia",
        "--code-coverage=user",
        "--project=$(runner_dir)",
        driver_path
    ]
    env = Dict(
        "TESTIMONIAL_FILE" => String(test_file),
        "TESTIMONIAL_ITEM" => String(item_name)
    )
    return (cmd, env)
end

"""
    record_item(ref) -> Union{ItemCoverage, Nothing}

Record coverage for a single @testitem by running it in an isolated subprocess.

Returns an `ItemCoverage` with the item's covered and uncovered lines, or
`nothing` if recording fails.

!!! note "Stub implementation"
    This is a placeholder that returns an empty `ItemCoverage`. The actual
    subprocess-based recording will be implemented in a follow-up
    (see testimonial-e47).
"""
function record_item(ref)
    # Stub: return empty coverage for now
    # Real implementation will:
    # 1. Create a temp directory with a symlinked shadow tree
    # 2. Determine the test file path relative to the project root
    # 3. Spawn a Julia subprocess running TestimonialRunner
    # 4. Parse the resulting .jl.cov sidecar
    # 5. Return ItemCoverage with covered/uncovered lines
    parent = Base.parentmodule(@__MODULE__)
    return parent.ItemCoverage(ref, Int[], Int[])
end

end # module CoverageLayer