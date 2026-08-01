# Quick test runner — excludes slow subprocess tests (test_protocol.jl,
# test_subprocess_record.jl, test_inference_capture.jl,
# test_inference_integration.jl, test_runner.jl).
# Includes only :quick-classified test files from the canonical manifest.
# Use via: just test-quick

using Testimonial, Test, Dates

include("helpers.jl")
include("manifest.jl")

# ── Assert manifest completeness ────
result = check_manifest_completeness()
if !isempty(result.unclassified)
    error("""
    Unclassified test files in test/:
      $(join(result.unclassified, "\n  "))
    Add each to TEST_MANIFEST in test/manifest.jl as :quick or :slow.
    """)
end
@info "Test manifest: $(length(quick_tests())) quick (excluded: $(length(slow_tests())) slow)"

# ── Run only quick tests ────
@testset "Quick tests" begin
    for f in quick_tests()
        include(f)
    end
end