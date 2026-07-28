#!/usr/bin/env julia
#
# TestimonialRunner driver.jl — subprocess entry point for recording coverage
# of individual @testitems.
#
# Usage:
#   TESTIMONIAL_FILE=test/my_test.jl TESTIMONIAL_ITEM="My test" julia driver.jl
#   TESTIMONIAL_FILE=test/my_test.jl TESTIMONIAL_ITEMS="My test\nOther test" julia driver.jl
#
# Reads TESTIMONIAL_FILE and either TESTIMONIAL_ITEM (single) or
# TESTIMONIAL_ITEMS (newline-separated batch) from the environment, runs
# the specified @testitem(s) via ReTestItems.runtests, and exits with
# a status code indicating the outcome.
#
# Batch mode runs every named item sequentially within one Julia process;
# the LCOV tracefile therefore holds the UNION of coverage across the
# batch (safe over-approximation attributed per-item by the caller).
#
# Exit codes:
#   0 — Success (test ran, result printed to stdout)
#   2 — Internal Error (unhandled exception in the driver itself)
#   3 — Setup Error (missing env vars, file not found, dependency issue)
#
# Note: Test pass/fail is reported in stdout output, not via exit code.
# ReTestItems.runtests does not throw on test failures.
#
# See REC-009 in openspec/changes/implement-coverage-layer/specs/recording/spec.md

using ReTestItems
using Pkg

# ── Read environment ──────────────────────────

test_file = get(ENV, "TESTIMONIAL_FILE", nothing)
test_item = get(ENV, "TESTIMONIAL_ITEM", nothing)
test_items_raw = get(ENV, "TESTIMONIAL_ITEMS", nothing)

if test_file === nothing
    println(stderr, "driver.jl: missing TESTIMONIAL_FILE")
    exit(3)
end

# Batch form takes precedence; single-item form is the fallback.
item_names = if test_items_raw !== nothing
    filter(!isempty, split(test_items_raw, "\n"))
else
    test_item === nothing ? String[] : String[test_item]
end

if isempty(item_names)
    println(stderr, "driver.jl: missing TESTIMONIAL_ITEM or TESTIMONIAL_ITEMS")
    exit(3)
end

if !isfile(test_file)
    println(stderr, "driver.jl: test file not found: $(test_file)")
    exit(3)
end

# ── Activate the project under test ──────────
# The test file belongs to a project (e.g., TestJuliaAdapter).
# Walk up from the test file to find a Project.toml and activate it
# so ReTestItems can find the @testitem blocks and the project's deps.
test_dir = dirname(realpath(test_file))
function _find_project_root(start_dir)
    d = start_dir
    while true
        if isfile(joinpath(d, "Project.toml"))
            return d
        end
        parent = dirname(d)
        if parent == d
            return dirname(start_dir)
        end
        d = parent
    end
end
pkg_under_test = _find_project_root(test_dir)

# Add the project to the load path so ReTestItems can find its test files
push!(LOAD_PATH, pkg_under_test)

# ── Run the test(s) ─────────────────────────

try
    for item in item_names
        ReTestItems.runtests(test_file; name=item)
    end
    # runtests prints results to stdout; if it returns without
    # throwing, the test ran successfully (exit 0).
    # Test failures are reported in the output but don't throw.
    exit(0)
catch e
    if e isa ArgumentError || e isa SystemError || e isa ReTestItems.NoTestException
        println(stderr, "driver.jl: setup error: $(sprint(showerror, e))")
        exit(3)
    else
        println(stderr, "driver.jl: internal error: $(sprint(showerror, e))")
        exit(2)
    end
end