# Full test runner — includes every `test_*.jl` via canonical manifest.
# CI uses runtests_quick.jl instead; runtests.jl is the full Pkg.test suite.
#
# Run: just test  (or  julia --project test/runtests.jl)

using Testimonial
using Test
using Dates

include("helpers.jl")
include("manifest.jl")

# ── Assert manifest completeness ───────────────
# Every test_*.jl must be classified in test/manifest.jl.
# Adding a file without classification is an error.
result = check_manifest_completeness()
if !isempty(result.unclassified)
    error("""
    Unclassified test files in test/:
      $(join(result.unclassified, "\n  "))
    Add each to TEST_MANIFEST in test/manifest.jl as :quick or :slow.
    """)
end
@info "Test manifest: $(length(full_tests())) total ($(length(quick_tests())) quick, $(length(slow_tests())) slow)"

# ── Include all test files ─────────────────────
for f in full_tests()
    include(f)
end