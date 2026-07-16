#!/usr/bin/env julia
#
# TestimonialRunner driver.jl — subprocess entry point for recording coverage
# of individual @testitems.
#
# Usage:
#   TESTIMONIAL_FILE=test/my_test.jl TESTIMONIAL_ITEM="My test" julia driver.jl
#
# Reads TESTIMONIAL_FILE and TESTIMONIAL_ITEM from the environment, runs
# only that specific @testitem via ReTestItems.runtests, and exits with
# a status code indicating the outcome.
#
# Exit codes:
#   0 — Success (test passed)
#   1 — Test Failed (assertion failure or runtime error in the test)
#   2 — Internal Error (unhandled exception in the driver itself)
#   3 — Setup Error (missing env vars, file not found, dependency issue)
#
# See REC-009 in openspec/changes/implement-coverage-layer/specs/recording/spec.md

using ReTestItems

# ── Read environment ──────────────────────────

test_file = get(ENV, "TESTIMONIAL_FILE", nothing)
test_item = get(ENV, "TESTIMONIAL_ITEM", nothing)

if test_file === nothing || test_item === nothing
    println(stderr, "driver.jl: missing TESTIMONIAL_FILE or TESTIMONIAL_ITEM")
    exit(3)
end

if !isfile(test_file)
    println(stderr, "driver.jl: test file not found: $(test_file)")
    exit(3)
end

# ── Run the test ──────────────────────────────

try
    results = ReTestItems.runtests(; files=[test_file], names=[test_item])

    if all(r -> r.passed, results)
        exit(0)
    else
        exit(1)
    end
catch e
    if e isa ArgumentError || e isa SystemError
        println(stderr, "driver.jl: setup error: $(sprint(showerror, e))")
        exit(3)
    else
        println(stderr, "driver.jl: internal error: $(sprint(showerror, e))")
        exit(2)
    end
end