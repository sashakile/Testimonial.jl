# test/manifest.jl — canonical test file manifest
#
# Every test_*.jl in test/ must be classified as :quick or :slow.
# Adding a new test_*.jl without classification fails CI.
# Both runtests.jl and runtests_quick.jl derive their include lists
# from this manifest (see full_tests() and quick_tests() below).
#
# Convention:
#   :quick — fast tests (< 1s), no subprocess spawning. Run in CI.
#   :slow  — subprocess-heavy (record_item, protocol adapter, inference
#            capture). Run in full suite only.
#
# IMPORTANT: When adding a new test_*.jl, add it here FIRST. The CI
# completeness check will fail until it's classified.

const TEST_MANIFEST = Pair{String, Symbol}[
    # ── Quick tests (< 1s, no subprocess spawning) ────
    # Core types and persistance
    "test_types.jl" => :quick,
    "test_persistence.jl" => :quick,

    # Parser and diff
    "test_astparser.jl" => :quick,
    "test_gitdiff.jl" => :quick,

    # Commands and runners (non-subprocess types)
    "test_command.jl" => :quick,
    "test_runner_types.jl" => :quick,

    # Index building and mock recording
    "test_indexbuilder.jl" => :quick,
    "test_mockrunner.jl" => :quick,

    # Coverage sidecar and timeout
    "test_cov_sidecar.jl" => :quick,
    "test_timeout.jl" => :quick,

    # Driver and change detection
    "test_driver.jl" => :quick,
    "test_changed_detection.jl" => :quick,

    # Query layer
    "test_query.jl" => :quick,
    "test_query_chain.jl" => :quick,
    "test_format_reason.jl" => :quick,
    "test_explain_exclude.jl" => :quick,

    # Record all and batching
    "test_record_all.jl" => :quick,
    "test_batching.jl" => :quick,
    "test_build_index_integration.jl" => :quick,

    # CLI (entry, main, shadow mode)
    "test_cli.jl" => :quick,
    "test_cli_entry.jl" => :quick,
    "test_shadow_mode.jl" => :quick,

    # Always-run and environment fingerprint
    "test_always_run.jl" => :quick,
    "test_environment_fingerprint.jl" => :quick,

    # Must-run rules
    "test_must_run_config.jl" => :quick,
    "test_must_run_query.jl" => :quick,
    "test_must_run_priority.jl" => :quick,
    "test_must_run_integration.jl" => :quick,

    # Scoped fallback
    "test_scoped_fallback.jl" => :quick,

    # Seeded-fault tests (fast, no real subprocess)
    "test_seeded_fault.jl" => :quick,
    "test_seeded_fault_verify.jl" => :quick,

    # Provenance and impact reasoning
    "test_provenance_link.jl" => :quick,
    "test_impact_reason_chain.jl" => :quick,
    "test_provenance_persistence.jl" => :quick,

    # LCOV tracefile parsing
    "test_lcov_tracefile.jl" => :quick,

    # Component system (discovery, graph, migration, persistence)
    "test_component_discovery.jl" => :quick,
    "test_component_bottom_up.jl" => :quick,
    "test_component_fingerprint.jl" => :quick,
    "test_components_override.jl" => :quick,
    "test_component_directory.jl" => :quick,
    "test_component_graph.jl" => :quick,
    "test_component_graph_persistence.jl" => :quick,
    "test_inter_component_edges.jl" => :quick,
    "test_load_index_components.jl" => :quick,
    "test_migrate_index.jl" => :quick,
    "test_record_all_components.jl" => :quick,

    # Confidence scoring
    "test_confidence.jl" => :quick,

    # Run history and sharding
    "test_run_history.jl" => :quick,
    "test_shard_balance.jl" => :quick,
    "test_shard_files.jl" => :quick,

    # Manual edges and incident lifecycle
    "test_manual_edges.jl" => :quick,
    "test_incident_lifecycle.jl" => :quick,

    # Reconciliation
    "test_reconcile.jl" => :quick,
    "test_reconciliation_report.jl" => :quick,

    # Flaky detector
    "test_flaky_detector.jl" => :quick,

    # Inference edges (lightweight — no subprocess in test)
    "test_inference_edges.jl" => :quick,

    # Static analysis (lightweight)
    "test_static_analysis.jl" => :quick,
    "test_static_integration.jl" => :quick,

    # Ingestion (fast query tests)
    "test_ingest.jl" => :quick,
    "test_ingested_run_prune.jl" => :quick,

    # ── Slow tests (subprocess-heavy) ────────────────
    # Protocol adapter: subprocess spawning under discover/ingest
    "test_protocol.jl" => :slow,

    # Subprocess recording: record_item spawns real Julia subprocesses
    "test_subprocess_record.jl" => :slow,

    # Inference capture: subprocess-heavy (SnoopCompile)
    "test_inference_capture.jl" => :slow,
    "test_inference_integration.jl" => :slow,

    # Test runner: subprocess orchestration
    "test_runner.jl" => :slow,
]

"""
    check_manifest_completeness() -> NamedTuple

Enumerate all `test_*.jl` files in test/ and compare against the manifest.
Returns unclassified (in dir but not in manifest) and orphans (in manifest
but missing from dir). Callers should error on non-empty unclassified.
"""
function check_manifest_completeness()
    dir = @__DIR__
    classified = Set{String}(k for (k, _) in TEST_MANIFEST)
    actual = Set{String}()
    for f in readdir(dir)
        startswith(f, "test_") && endswith(f, ".jl") && push!(actual, f)
    end
    return (
        unclassified = collect(sort!(collect(setdiff(actual, classified)))),
        orphans = collect(sort!(collect(setdiff(classified, actual)))),
    )
end

"""
    full_tests() -> Vector{String}

All test files to include in the full suite (just test / Pkg.test).
Includes both :quick and :slow files in manifest order.
"""
function full_tests()
    return [k for (k, _) in TEST_MANIFEST]
end

"""
    quick_tests() -> Vector{String}

Test files that run in the quick suite (CI / just test-quick).
Only :quick-classified files.
"""
function quick_tests()
    return [k for (k, v) in TEST_MANIFEST if v == :quick]
end

"""
    slow_tests() -> Vector{String}

Test files classified as :slow (excluded from quick mode).
"""
function slow_tests()
    return [k for (k, v) in TEST_MANIFEST if v == :slow]
end