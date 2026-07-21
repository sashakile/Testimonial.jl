#!/usr/bin/env julia
# seeded_fault_test.jl — Seeded fault recall test for Testimonial.jl
#
# Introduces a known semantic mutation into the source tree, runs test
# selection, and verifies that the fault-revealing test is selected.
# Exit code is non-zero if any fault's revealing test is missed.
#
# Usage:
#   julia --project scripts/seeded_fault_test.jl          # Run all seeds
#   julia --project scripts/seeded_fault_test.jl new-function  # Run specific seed
#
# See: openspec/changes/add-safety-invariants/design.md § Decision 7

using Testimonial

"""Run a single seed pattern and report result."""
function run_pattern(pattern)
    println("─" ^ 60)
    println("Pattern:  $(pattern.name)")
    println("Action:   $(pattern.action)")
    println("Expect:   $(pattern.revealing_test)")
    println()

    # Run the verification
    result = Testimonial.run_seeded_fault_test(pattern)

    if result.passed
        println("✓ PASSED — $(result.selected_items) item(s) selected")
    else
        println("✗ FAILED — $(result.error)")
    end
    println()

    return result[:passed]
end

# ── Main ───────────────────────────────────────

all_passed = true
patterns = Testimonial.SEED_FAULT_PATTERNS

# Filter to specific pattern if requested
if length(ARGS) > 0
    name = ARGS[1]
    filtered = filter(p -> p.name == name, patterns)
    if isempty(filtered)
        println("Unknown pattern: $name")
        println("Available: $(join([p.name for p in patterns], ", "))")
        exit(1)
    end
    patterns = filtered
end

println("╔══════════════════════════════════════════════════════╗")
println("║       Testimonial.jl — Seeded Fault Recall Test      ║")
println("╚══════════════════════════════════════════════════════╝")
println()
println("Running $(length(patterns)) seed pattern(s)...")
println()

for pattern in patterns
    passed = run_pattern(pattern)
    all_passed = all_passed && passed
end

println("─" ^ 60)
if all_passed
    println("✓ ALL SEEDS PASSED — selection is correct")
    exit(0)
else
    println("✗ SOME SEEDS FAILED — review error messages above")
    exit(1)
end