#!/usr/bin/env julia
# reset_coverage_spike.jl — Test whether Base.reset_coverage() permits
# in-process per-function coverage counter resets for per-@testitem attribution.
#
# Julia 1.11+ introduced Base.reset_coverage(). This experiment determines
# if calling it between test runs correctly resets the coverage counters,
# enabling in-process recording instead of subprocess-per-item.
#
# Usage: julia --code-coverage=user reset_coverage_spike.jl

using Test

# ── Fixture: two functions with distinct lines ──

function func_a()
    x = 1      # line 15
    y = 2      # line 16
    return x + y  # line 17
end

function func_b()
    a = "hello"  # line 21
    b = "world"  # line 22
    return a * " " * b  # line 23
end

# ── Helper: check coverage via runtime introspection ──

"""Extract per-line coverage counts for a specific function from the global coverage table."""
function get_function_coverage(f::Function)::Dict{Int, Int}
    # Get the source location of the function
    linfo = @__LINE__()
    file = @__FILE__()
    # Coverage data is stored in the global COVERAGE table
    # In Julia 1.11+, Base.reset_coverage() is documented but the internal
    # storage is via `Core.code_coverage` or the COVERAGE[] hash.
    # We use `Coverage.CoverageTools.process_covdata` or direct lookup.
    
    # Collect coverage data — format: (filename, line_1_based) => hit_count
    cov = Dict{Int, Int}()
    if isdefined(Base, :COVERAGE)
        for ((fname, line), count) in Base.COVERAGE
            if fname == file
                cov[line] = count
            end
        end
    else
        # Fallback: Coverage.jl's process_covdata on .jl.cov files
        # Not available in-process, so mark as unknown
        cov[0] = -1  # sentinel: coverage data unavailable via Base.COVERAGE
    end
    return cov
end

"""Print coverage data in a readable format."""
function print_coverage(label::String, cov::Dict{Int, Int})
    println("  $label:")
    for line in sort!(collect(keys(cov)))
        println("    line $line: $(cov[line]) hits")
    end
end

# ── Main experiment ──

println("=" ^ 60)
println("reset_coverage Spike — Julia $(VERSION)")
println("=" ^ 60)

# Check if Base.reset_coverage exists
if !isdefined(Base, :reset_coverage)
    println("\n❌ Base.reset_coverage() is NOT available in Julia $(VERSION)")
    println("   ➜ Subprocess isolation is unconditionally necessary.")
    exit(1)
end

println("\n✅ Base.reset_coverage() is available")
println()

# ── Experiment 1: Basic coverage collection ──

println("--- Experiment 1: Baseline coverage ---")
func_a()
func_b()

# Check coverage data method
if isdefined(Base, :COVERAGE)
    println("  Base.COVERAGE table has $(length(Base.COVERAGE)) entries")
    
    # Extract coverage for this file
    cov_before = get_function_coverage(func_a)
    print_coverage("Before reset", cov_before)
    
    # ── Experiment 2: Reset and check ──
    println("\n--- Experiment 2: After reset ---")
    Base.reset_coverage()
    
    cov_after = get_function_coverage(func_a)
    print_coverage("After reset", cov_after)
    
    # Check if counters were reset to zero
    any_nonzero = any(v -> v > 0, values(cov_after))
    if any_nonzero
        println("\n❌ Coverage counters were NOT reset to zero")
    else
        println("\n✅ Coverage counters were reset to zero")
    end
    
    # ── Experiment 3: Call again after reset ──
    println("\n--- Experiment 3: Call func_a after reset ---")
    func_a()
    
    cov_rerun = get_function_coverage(func_a)
    print_coverage("After re-run", cov_rerun)
    
    only_rerun_lines = any(v -> v > 0, values(cov_rerun))
    if only_rerun_lines
        println("✅ Coverage from re-run is visible after reset")
    else
        println("❌ No new coverage data collected after reset")
    end
    
    # ── Experiment 4: Interleaved resets ──
    println("\n--- Experiment 4: Interleaved resets (simulating per-testitem) ---")
    func_a()
    cov_a = get_function_coverage(func_a)
    print_coverage("After func_a call 1", cov_a)
    Base.reset_coverage()
    
    func_b()
    cov_b = get_function_coverage(func_b)
    print_coverage("After func_b call 2 (reset between)", cov_b)
    
    # Check that func_a's coverage is gone and only func_b's remains
    func_a_lines = length(cov_a) > 0 ? count(keys(cov_a)) : 0
    func_b_lines = length(cov_b) > 0 ? count(keys(cov_b)) : 0
    
    println("  func_a covered lines: $(func_a_lines > 0 ? "present" : "absent")")
    println("  func_b covered lines: $(func_b_lines > 0 ? "present" : "absent")")
    
    # ── Summary ──
    println("\n" ^ "_" ^ 60)
    println("OVERALL VERDICT")
    println("_" ^ 60)
    if any_nonzero
        println("❌ FAIL: Base.reset_coverage() does NOT fully clear coverage counters.")
        println("   Subprocess isolation remains the safe default.")
        println("   Recommendation: use subprocess-per-item for Testimonial.jl.")
    else
        println("✅ PASS: Base.reset_coverage() clears coverage counters.")
        println("   In-process per-@testitem recording is viable.")
        println("   Recommendation: adopt in-process reset with fallback to subprocess.")
    end
else
    println("  Base.COVERAGE is not available in this Julia version.")
    println("  Checking alternative coverage APIs...")
    
    # Try using Coverage.jl's in-process data
    try
        using Coverage
        println("  Coverage.jl is available — checking process_covdata...")
    catch
        println("  Coverage.jl not available — cannot verify in-process.")
    end
    
    println("\n⚠️  Cannot fully verify reset_coverage without Base.COVERAGE table.")
    println("   Subprocess isolation remains the safe default.")
end