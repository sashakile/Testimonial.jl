## 1. Always-run set integration into smart_run
- [x] 1.1 Define `AlwaysRunReason` enum (`LAST_RUN_FAILED`, `NEWLY_ADDED`, `NO_HISTORY`, `QUARANTINED`)
- [x] 1.2 Add `always_run_reason::Union{Nothing, AlwaysRunReason}` to `TestItemRef` or a sidecar metadata struct
- [x] 1.3 Modify `smart_run` to union always-run set into selected items before the max-cap check
- [x] 1.4 Implement always-run eviction: test exits always-run set after N consecutive passes
- [x] 1.5 Write tests for always-run composition and eviction

## 2. Scoped fallback on unresolved content
- [x] 2.1 Add `fallback_reason::Union{Nothing, FallbackReason}` to `ImpactResult`
- [x] 2.2 Modify `query` to signal unresolved files or unmodeled content
- [x] 2.3 Implement scoped fallback: only the affected component falls back to full run
- [x] 2.4 Implement pre-component-boundary degradation: scoped = global fallback until component graph exists
- [x] 2.5 Write tests for scoped and degraded fallback

## 3. Environment change detection
- [x] 3.1 Store environment fingerprint (Julia version + `Project.toml` hash) in `CoverageIndex`
- [x] 3.2 Check fingerprint on `smart_run` load; trigger full suite fallback on mismatch
- [x] 3.3 Write tests for environment change detection

## 4. Must-run rules
- [x] 4.1 Define `MustRunRule` config struct (glob pattern → test tag or name)
- [x] 4.2 Add `must_run` section to `Testimonial.toml` schema (Phase 3 config)
- [x] 4.3 Apply must-run rules during `query`: force-select matching tests on changed file match
- [x] 4.4 Implement must-run + scoped-fallback priority: scoped fallback wins, must-run logged
- [x] 4.5 Write tests for must-run rules and priority

## 5. Flaky detection and quarantine
- [x] 5.1 Implement flaky detector (inconsistent outcomes across retries → flaky label)
- [x] 5.2 Add quarantine metadata: test is selected and run, outcome excluded from pass/fail
- [x] 5.3 Add flaky test edge exclusion: runtime edges from flaky tests not ingested (FEED-002 interaction)
- [x] 5.4 Write tests for flaky detection, quarantine, and edge exclusion

## 6. Missed-selection incident recording
- [x] 6.1 Define `MissedSelectionIncident` struct (changed content, missed test, timestamp, status: candidate|promoted|dismissed)
- [x] 6.2 Store incidents in `.testimonial/incidents.jls` (separate from index, survives rebuilds)
- [x] 6.3 Implement candidate → promoted promotion logic (same failure across 3 changes)
- [x] 6.4 Add `testimonial incidents` CLI command to list and dismiss incidents
- [x] 6.5 On promotion, create a `manual` edge in the index forcing selection next time
- [x] 6.6 Write tests for incident lifecycle (candidate, promote, dismiss)
- [x] 6.7 **(depends on:** `add-runtime-feedback` ingest phase)

## 7. Shadow mode
- [x] 7.1 Add `shadow::Bool` keyword argument to `smart_run`
- [x] 7.2 In shadow mode: compute selection, log it, but run all tests
- [x] 7.3 Compare selected set against full-run outcomes; log any candidate incidents
- [x] 7.4 Add `--shadow` flag to CLI
- [x] 7.5 Write tests for shadow mode logging and incident detection

## 8. Full-run reconciliation
- [x] 8.1 Implement `reconcile()` function that runs all tests + computes counterfactual selection
- [x] 8.2 Persist reconciliation report to `.testimonial/reconciliation/`
- [x] 8.3 Create a CI workflow definition for scheduled reconciliation runs
- [x] 8.4 Write tests for reconciliation computation and reporting

## 9. Seeded-fault recall test
- [x] 9.1 Create `scripts/seeded_fault_test.jl`
- [x] 9.2 Define 3–5 seed patterns covering common cases (new function, modified function, new file, deleted file, multiple files)
- [x] 9.3 For each seed: introduce fault, run selection, verify fault-revealing test is selected
- [x] 9.4 Exit non-zero on any missed selection
- [x] 9.5 Write tests for the test itself (verify seeds are valid and detectable)
- [x] 9.6 Add `just seed-fault-test` command

## 10. Promotion protocol
- [x] 10.1 Add `mode` config key to `Testimonial.toml`: `shadow` | `enforcing` (default: `shadow`)
- [x] 10.2 Implement evaluation window tracking (record PR count and time since deployment)
- [x] 10.3 Log promotion readiness status in `index_info` output
- [x] 10.4 Document the promotion protocol in `README.md`