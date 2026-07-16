# Coverage recording layer — records coverage for individual @testitems.
#
# Runs each @testitem in an isolated subprocess and parses the resulting
# .jl.cov sidecar files to attribute covered lines back to the item.
#
# See PROTO-004 in openspec/changes/implement-coverage-layer/specs/protocol-adapter/spec.md

module CoverageLayer

export record_item

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