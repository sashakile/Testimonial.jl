#!/usr/bin/env julia
#
# reconcile_run.jl — scheduled reconciliation runner
#
# Runs the full test suite, computes the counterfactual smart selection,
# and calls Testimonial.reconcile() to detect any missed-selection incidents.
#
# Usage:
#   julia --project scripts/reconcile_run.jl [--base-ref <ref>]
#
# Environment:
#   JULIA_NUM_THREADS  — thread count for parallel operations (default: 2)
#
# Exit codes:
#   0 — Reconciliation completed (incidents may have been detected)
#   1 — Reconciliation failed (setup error, test failure, etc.)
#
# See SAFE-009, CI-INT-012 in openspec/changes/add-safety-invariants/

using Testimonial
using Testimonial.CLI
using Dates
using Serialization

# ── Configuration ──────────────────────────────

BASE_REF = "origin/main"
for (i, arg) in enumerate(ARGS)
    if arg == "--base-ref" && i < length(ARGS)
        global BASE_REF = ARGS[i + 1]
    end
end

# ── Helpers ────────────────────────────────────

"""
    _run_all_tests() -> (all_items::Vector{TestItemRef}, failed_items::Vector{TestItemRef})

Run the full test suite using Pkg.test() and collect test item references.
Returns the list of all items and the subset that failed.

Caveat: ReTestItems.runtests() prints results to stdout rather than returning
structured pass/fail data per @testitem. The `failed_items` return relies on
ReTestItems' `report` keyword or test-result callbacks, which are project-
dependent. When ReTestItems is configured with structured reporting (e.g.,
JSON reports), this function should parse those to populate `failed_items`.

Currently, `failed_items` is derived from the Pkg.test() exit code:
- If Pkg.test() succeeds → no failed items (optimistic — avoids false incidents)
- If Pkg.test() fails → all items are marked as `failed_items` (conservative —
  may produce spurious incidents; refine with structured reporting)

Tracked in: testimonial-hye follow-up
"""
function _run_all_tests()::Tuple{Vector{TestItemRef}, Vector{TestItemRef}}
    @info "Running full test suite..."

    # Discover all test items
    items = discover_testitems(["test/"])
    @info "Discovered $(length(items)) test items"

    all_items = copy(items)

    # Run tests using Pkg.test() in a subprocess to capture exit code
    @info "Invoking Pkg.test()..."
    project_root = dirname(@__DIR__)
    test_cmd = `$(Base.julia_cmd()) --project=$(project_root) -e '
        import Pkg
        Pkg.test()
    '`
    test_result = try
        Base.run(test_cmd)
        true  # success
    catch e
        if e isa Base.IOError || e isa Base.ProcessFailedException
            false  # test failure / non-zero exit
        else
            rethrow()
        end
    end

    if test_result
        @info "All tests passed"
        return all_items, TestItemRef[]
    else
        @warn "Some tests failed — marking all items as potentially failed"
        @warn "Refine with structured ReTestItems reporting in follow-up"
        return all_items, all_items  # conservative: all items are suspects
    end
end

"""
    _get_changed_summary(base_ref::String) -> String

Get a summary of changed files since base_ref, for use as the
`changed_content` label in reconciliation.
"""
function _get_changed_summary(base_ref::String)::String
    try
        diff = read(`git diff $(base_ref)...HEAD --name-only`, String)
        files = split(strip(diff), "\n", keepempty=false)
        if isempty(files)
            return "no-changes"
        end
        return join(files, ",")
    catch e
        @warn "Could not get git diff: $e"
        return "unknown-changes"
    end
end

"""
    _print_report(report::NamedTuple, selected_count::Int, all_count::Int)

Print a human-readable reconciliation report summary.
"""
function _print_report(report::NamedTuple, selected_count::Int, all_count::Int)::Nothing
    println("─"^60)
    println("RECONCILIATION REPORT")
    println("─"^60)
    println("  Timestamp:              $(Dates.format(report.timestamp, "yyyy-mm-dd HH:MM:SS"))")
    println("  Full suite:             $(all_count) items")
    println("  Counterfactual selected: $(selected_count) items")
    println("  Incidents detected:     $(report.incidents_detected)")
    println("  Incidents promoted:     $(report.incidents_promoted)")
    println("  Manual edges created:   $(report.manual_edges_created)")
    println("  Total incidents:        $(report.total_incidents)")
    println("  Total manual edges:     $(report.total_manual_edges)")
    println("  Quarantined excluded:   $(report.quarantined_excluded)")

    if report.incidents_detected > 0
        println("─"^60)
        println("⚠  $(report.incidents_detected) missed-selection incident(s) detected!")
        println("   Run `julia --project -e 'using Testimonial; index_info()'` for details.")
        println("   Run `julia --project -e 'using Testimonial.CLI; CLI.main([\"incidents\"])'` to list incidents.")
    end
    println("─"^60)
    return nothing
end

"""
    _save_report_json(report::NamedTuple)

Save a JSON-formatted summary of the reconciliation report for CI consumption.
"""
function _save_report_json(report::NamedTuple)::Nothing
    mkpath(".testimonial")
    json_path = joinpath(".testimonial", "reconciliation_latest.json")
    open(json_path, "w") do io
        println(io, "{")
        println(io, "  \"timestamp\": \"$(Dates.format(report.timestamp, "yyyy-mm-ddTHH:MM:SS"))\",")
        println(io, "  \"incidents_detected\": $(report.incidents_detected),")
        println(io, "  \"incidents_promoted\": $(report.incidents_promoted),")
        println(io, "  \"manual_edges_created\": $(report.manual_edges_created),")
        println(io, "  \"total_incidents\": $(report.total_incidents),")
        println(io, "  \"total_manual_edges\": $(report.total_manual_edges),")
        println(io, "  \"quarantined_excluded\": $(report.quarantined_excluded)")
        println(io, "}")
    end
    return nothing
end

# ── Main ───────────────────────────────────────

function main()::Int
    @info "Starting scheduled reconciliation run"
    @info "Base ref: $(BASE_REF)"

    # Step 1: Get changed content summary
    changed_summary = _get_changed_summary(BASE_REF)
    @info "Changed content: $(changed_summary)"

    # Step 2: Compute counterfactual smart selection
    @info "Computing counterfactual smart selection..."
    selection = CLI.run(; base_ref=BASE_REF, shadow=false)

    # Step 3: Run all tests
    all_items, failed_items = _run_all_tests()

    # Step 4: Extract selected items
    selected_items = if selection isa Symbol
        @info "Smart selection returned: $(selection) — running full suite"
        all_items
    else
        selected_items = [r.item for r in selection]
        @info "Smart selection: $(length(selected_items)) of $(length(all_items)) items"
        selected_items
    end

    # Step 5: Run reconciliation
    @info "Running reconciliation..."
    report = Testimonial.reconcile(
        selected_items,
        all_items,
        failed_items,
        changed_summary;
        promote_threshold=3,
    )

    # Step 6: Print and persist report
    _print_report(report, length(selected_items), length(all_items))
    _save_report_json(report)

    @info "Reconciliation complete. Incidents: $(report.incidents_detected), Promoted: $(report.incidents_promoted)"

    # Exit code: 0 even if incidents detected (incidents are expected and tracked)
    return 0
end

# ── Entry point ────────────────────────────────

exit(main())