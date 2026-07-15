# Change: Fix Spec Foundations — Resolve 9 Findings from Specification Evaluation

> **Status (two-layer architecture): NARROWED scope.** Several fixes are now
> moot because the 5 proposals they targeted are deferred (`confidence-scoring`,
> `provenance-explainability`, `runtime-feedback`) or have reduced scope
> (`safety-invariants` protocol layer). Only the fixes that touch the Phase 1
> core or the remaining active proposals remain.

## Why

A high-fidelity specification evaluation (2026-07-15) found 9 findings across all 6 OpenSpec change proposals, from correctness errors (inverted formula, conflicting thresholds) to structural issues (capability naming mismatch, circular dependency, orphaned requirements, unverifiable citations). All proposals are at 0/N tasks — fixing now avoids building on a broken foundation.

The evaluation report is archived as a wai research document: `wai search "spec evaluation"`.

## What Changes

### Still applies (keep):

Completeness fixes to `implement-coverage-layer`:
- Add missing scenario to REC-011 in `implement-coverage-layer` (COMP-1.1)
- Add `layer_data` and `manual_edges` field definitions to CI-001 (COMP-1.2) —
  already done in the Phase 1 design
- Add testaruda to `project.md` References section (COHR-3.4) — already done
  with the two-layer architecture update

### Moot (drop from scope):

Formula and threshold fixes to `add-confidence-scoring` (CORR-2.1, CORR-2.2):
- Confidence scoring is **deferred indefinitely** — no point fixing a spec that
  won't be implemented

Circular dependency resolution between `add-runtime-feedback` and
`add-safety-invariants` (COHR-3.3):
- Both proposals are deferred (runtime-feedback) or have reduced scope
  (safety-invariants). The circular dependency resolution only matters when
  both are implemented.

Structural fixes to deferred proposals (COHR-3.1, COMP-3.2):
- Capability naming mismatches and delta-completeness fixes for
  `confidence-scoring`, `provenance-explainability`, `runtime-feedback` are
  moot while those proposals are deferred.
- The `add-component-boundary` structural fixes still apply since it is **kept**.

Missing dependency to `add-confidence-scoring/proposal.md` (COMP-1.3):
- Moot while confidence-scoring is deferred.

Move "No git repository" scenario from COMP-001 to appropriate requirement
(COHR-3.5):
- COMP-001 is in the component-boundary proposal, which is kept.

## Impact

- Affected capabilities (New): none — this is a spec-only cleanup
- Affected specs (MODIFIED):
  - `coverage-index` — CI-001 gains `layer_data` field; CI-004 dropped stale `layer_data` ref
  - `record` — REC-011 gains a scenario
- Affected changes (MODIFIED files in `openspec/changes/`):
  - `add-component-boundary` — spec folder renamed, MODIFIED deltas added (still applies)
  - `implement-coverage-layer` — REC-011 + CI-001 fixes (still applies)
- `openspec/project.md` — two-layer architecture update (supersedes the original COHR-3.4)
- Dependencies: nothing — this is strictly a spec cleanup, no code changes