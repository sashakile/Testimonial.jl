## 1. Always-run set integration into smart_run
- [ ] 1.1 Define `AlwaysRunReason` enum (`LAST_RUN_FAILED`, `NEWLY_ADDED`, `NO_HISTORY`, `QUARANTINED`)
- [ ] 1.2 Add `always_run_reason::Union{Nothing, AlwaysRunReason}` to `TestItemRef` or a sidecar metadata struct
- [ ] 1.3 Modify `smart_run` to union always-run set into selected items before the max-cap check
- [ ] 1.4 Implement always-run eviction: test exits always-run set after N consecutive passes
- [ ] 1.5 Write tests for always-run composition and eviction

## 2. Scoped fallback on unresolved content
- [ ] 2.1 Add `fallback_reason::Union{Nothing, FallbackReason}` to `ImpactResult`
- [ ] 2.2 Modify `query` to signal unresolved files or unmodeled content
- [ ] 2.3 Implement scoped fallback: only the affected component falls back to full run
- [ ] 2.4 Implement pre-component-boundary degradation: scoped = global fallback until component graph exists
- [ ] 2.5 Write tests for scoped and degraded fallback

## 3. Environment change detection
- [ ] 3.1 Store environment fingerprint (Julia version + `Project.toml` hash) in `CoverageIndex`
- [ ] 3.2 Check fingerprint on `smart_run` load; trigger full suite fallback on mismatch
- [ ] 3.3 Write tests for environment change detection

## 4. Must-run rules
- [ ] 4.1 Define `MustRunRule` config struct (glob pattern → test tag or name)
- [ ] 4.2 Add `must_run` section to `Testimonial.toml` schema (Phase 3 config)
- [ ] 4.3 Apply must-run rules during `query`: force-select matching tests on changed file match
- [ ] 4.4 Implement must-run + scoped-fallback priority: scoped fallback wins, must-run logged
- [ ] 4.5 Write tests for must-run rules and priority

## 5. Flaky detection and quarantine
- [ ] 5.1 Implement flaky detector (inconsistent outcomes across retries → flaky label)
- [ ] 5.2 Add quarantine metadata: test is selected and run, outcome excluded from pass/fail
- [ ] 5.3 Add flaky test edge exclusion: runtime edges from flaky tests not ingested (FEED-002 interaction)
- [ ] 5.4 Write tests for flaky detection, quarantine, and edge exclusion

## 6. Missed-selection incident recording
- [ ] 6.1 Define `MissedSelectionIncident` struct (changed content, missed test, timestamp, status: candidate|promoted|dismissed)
- [ ] 6.2 Store incidents in `.testimonial/incidents.jls` (separate from index, survives rebuilds)
- [ ] 6.3 Implement candidate → promoted promotion logic (same failure across 3 changes)
- [ ] 6.4 Add `testimonial incidents` CLI command to list and dismiss incidents
- [ ] 6.5 On promotion, create a `manual` edge in the index forcing selection next time
- [ ] 6.6 Write tests for incident lifecycle (candidate, promote, dismiss)
- [ ] 6.7 **(depends on:** `add-runtime-feedback` ingest phase)

## 7. Shadow mode
- [ ] 7.1 Add `shadow::Bool` keyword argument to `smart_run`
- [ ] 7.2 In shadow mode: compute selection, log it, but run all tests
- [ ] 7.3 Compare selected set against full-run outcomes; log any candidate incidents
- [ ] 7.4 Add `--shadow` flag to CLI
- [ ] 7.5 Write tests for shadow mode logging and incident detection

## 8. Full-run reconciliation
- [ ] 8.1 Implement `reconcile()` function that runs all tests + computes counterfactual selection
- [ ] 8.2 Persist reconciliation report to `.testimonial/reconciliation/`
- [ ] 8.3 Create a CI workflow definition for scheduled reconciliation runs
- [ ] 8.4 Write tests for reconciliation computation and reporting

## 9. Seeded-fault recall test
- [ ] 9.1 Create `scripts/seeded_fault_test.jl`
- [ ] 9.2 Define 3–5 seed patterns covering common cases (new function, modified function, new file, deleted file, multiple files)
- [ ] 9.3 For each seed: introduce fault, run selection, verify fault-revealing test is selected
- [ ] 9.4 Exit non-zero on any missed selection
- [ ] 9.5 Write tests for the test itself (verify seeds are valid and detectable)
- [ ] 9.6 Add `just seed-fault-test` command

## 10. Promotion protocol
- [ ] 10.1 Add `mode` config key to `Testimonial.toml`: `shadow` | `enforcing` (default: `shadow`)
- [ ] 10.2 Implement evaluation window tracking (record PR count and time since deployment)
- [ ] 10.3 Log promotion readiness status in `index_info` output
- [ ] 10.4 Document the promotion protocol in `README.md`