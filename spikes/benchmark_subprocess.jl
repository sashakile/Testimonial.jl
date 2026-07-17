#!/usr/bin/env julia
# SPDX-License-Identifier: MIT
#
# Spike: Benchmark subprocess overhead for 1000+ items.
using Dates
#
# Measures the overhead of spawning Julia subprocesses for recording
# coverage. Uses nanosecond timing for precision.
#
# Success: <2s overhead per 1000 items on standard CI hardware.

# ── Helpers ───────────────────────────────────

"""Run a one-shot Julia subprocess and return (exitcode, elapsed_ns)."""
function bench_subprocess(code::String)
    cmd = `julia -e $(code)`
    start = time_ns()
    proc = run(pipeline(ignorestatus(cmd); stdout=devnull, stderr=devnull))
    elapsed = time_ns() - start  # nanoseconds
    return (proc.exitcode, elapsed)
end

"""Measure the time to spawn and run N sequential subprocesses."""
function bench_n_sequential(n::Int, label::String)
    println("\n═══ $label (n=$n) ═══")

    times = Float64[]  # nanoseconds
    for i in 1:n
        _, elapsed = bench_subprocess("println($i)")
        push!(times, elapsed)
    end
    total_ns = sum(times)
    avg_ns = total_ns / n
    per_1000_s = (avg_ns * 1000) / 1e9  # seconds per 1000 items

    println("  Total:    $(round(total_ns / 1e6, digits=1)) ms")
    println("  Average:  $(round(avg_ns / 1e6, digits=2)) ms")
    println("  Min:      $(round(minimum(times) / 1e6, digits=2)) ms")
    println("  Max:      $(round(maximum(times) / 1e6, digits=2)) ms")
    println("  Per 1000: $(round(per_1000_s, digits=2)) s")

    if per_1000_s < 2.0
        println("  ✓ PASS: $(round(per_1000_s, digits=2))s < 2s threshold")
    else
        println("  ✗ FAIL: $(round(per_1000_s, digits=2))s ≥ 2s threshold")
    end
    return per_1000_s
end

"""Measure the time to spawn N subprocesses using Threads.@threads."""
function bench_n_parallel(n::Int, nthreads::Int, label::String)
    println("\n═══ $label (n=$n, threads=$nthreads) ═══")

    if Threads.nthreads() < nthreads
        println("  ⚠ Not enough threads (need $nthreads, have $(Threads.nthreads()))")
        return Inf
    end

    times = Vector{Float64}(undef, n)
    t_start = time_ns()
    Threads.@threads for i in 1:n
        _, elapsed = bench_subprocess("println($i)")
        times[i] = elapsed
    end
    t_total_ns = time_ns() - t_start

    avg_ns = sum(times) / n
    per_1000_s = (t_total_ns / n) * 1000 / 1e9
    println("  Wall time: $(round(t_total_ns / 1e6, digits=1)) ms")
    println("  Average:   $(round(avg_ns / 1e6, digits=2)) ms per subprocess")
    println("  Per 1000:  $(round(per_1000_s, digits=2)) s")

    if per_1000_s < 2.0
        println("  ✓ PASS: $(round(per_1000_s, digits=2))s < 2s threshold")
    else
        println("  ✗ FAIL: $(round(per_1000_s, digits=2))s ≥ 2s threshold")
    end
    return per_1000_s
end

println("═══ Subprocess Overhead Benchmark ═══")
println("Julia: $(VERSION)")
println("CPU threads: $(Threads.nthreads())")
println("Date: $(string(Dates.now()))")

available = try parse(Int, read(`nproc`, String)) catch; 4 end
println("Available CPUs: $available")
println("Julia threads:  $(Threads.nthreads())")

# Warmup JIT
print("  Warming up JIT...")
bench_subprocess("println(1)")
println(" done")

# ── Benchmarks ───────────────────────────────

for n in [1, 10, 50]
    bench_n_sequential(n, "Empty subprocess (sequential)")
end

if Threads.nthreads() >= 2
    bench_n_parallel(50, min(Threads.nthreads(), available), "Empty subprocess (parallel)")
end

# ── Estimate for 1000 items ─────────────────
println("\n═══ Projected estimate for 1000 items ═══")
time_1_ns = bench_subprocess("println(1)")[2]
time_1_ms = time_1_ns / 1e6
println("  Single subprocess: $(round(time_1_ms, digits=2)) ms")
println("  * 1000 sequential:  $(round(time_1_ms * 1000 / 1000, digits=2)) s")
println("  * 1000 parallel-4:  $(round(time_1_ms * 1000 / 1000 / min(4, Threads.nthreads()), digits=2)) s")
println("  * 1000 parallel-8:  $(round(time_1_ms * 1000 / 1000 / min(8, Threads.nthreads()), digits=2)) s")

# ── Realistic estimate with driver.jl ───────
println("\n═══ Realistic estimate (with driver.jl overhead) ═══")
# driver.jl is more expensive than an empty -e — it loads ReTestItems
# and the test project. Add a realistic overhead multiplier.
time_with_driver_ms = try
    runner = "scripts/TestimonialRunner"
    cmd = `julia --project=$(runner) -e 'println("driver-load-check")'`
    start = time_ns()
    run(pipeline(ignorestatus(cmd); stdout=devnull, stderr=devnull))
    (time_ns() - start) / 1e6
catch
    time_1_ms * 5  # fallback estimate: 5x overhead
end
println("  Estimated driver.jl subprocess: $(round(time_with_driver_ms, digits=1)) ms")
println("  * 1000 sequential:              $(round(time_with_driver_ms * 1000 / 1000, digits=1)) s")
println("  * 1000 parallel-4:              $(round(time_with_driver_ms * 1000 / 1000 / min(4, Threads.nthreads()), digits=1)) s")
println("  * 1000 parallel-8:              $(round(time_with_driver_ms * 1000 / 1000 / min(8, Threads.nthreads()), digits=1)) s")