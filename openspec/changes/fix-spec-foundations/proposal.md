# Change: Fix Spec Foundations — Resolve 9 Findings from Specification Evaluation

## Why

A high-fidelity specification evaluation (2026-07-15) found 9 findings across all 6 OpenSpec change proposals, from correctness errors (inverted formula, conflicting thresholds) to structural issues (capability naming mismatch, circular dependency, orphaned requirements, unverifiable citations). All proposals are at 0/N tasks — fixing now avoids building on a broken foundation.

The evaluation report is archived as a wai research document: `wai search "spec evaluation"`.

## What Changes

Structural fixes to 5 existing change proposals (COHR-3.1, COMP-3.2):
- Rename each `specs/<change-id>/` delta folder to the capability name declared in `project.md`
- Add proper `## MODIFIED Requirements` delta files where proposals claim cross-capability impact (currently only ADDED Requirements exist, missing the MODIFIED deltas for existing capabilities)

Formula and threshold fixes to `add-confidence-scoring` (CORR-2.1, CORR-2.2):
- Fix `design.md` `layer_coverage` formula: `1 / (n + 1)` → `n / (n + 1)`
- Reconcile confidence threshold default conflict: `spec.md` says 0.5, `design.md` and proposal say 0.7

Circular dependency resolution between `add-runtime-feedback` and `add-safety-invariants` (COHR-3.3):
- Move the flaky-test runtime-edge exclusion scenario from FEED-002 to SAFE-007 as a MODIFIED scenario, since it depends on SAFE-007 which exists in `add-safety-invariants`

Completeness fixes:
- Add missing scenario to REC-011 in `implement-coverage-layer` (COMP-1.1)
- Add `layer_data` and `manual_edges` field definitions to CI-001 (COMP-1.2)
- Add missing `add-component-boundary` dependency to `add-confidence-scoring/proposal.md` (COMP-1.3)
- Add testaruda to `project.md` References section (COHR-3.4)
- Move "No git repository" scenario from COMP-001 to appropriate requirement (COHR-3.5)

## Impact

- Affected capabilities (New): none — this is a spec-only cleanup
- Affected specs (MODIFIED):
  - `confidence-scoring` — scenario in CONF-003 updated; formula fixed in design.md
  - `safety-invariants` — flaky-test runtime edge scenario moved from FEED-002 to MODIFIED SAFE-007
  - `coverage-index` — CI-001 gains `layer_data` field; CI-004 dropped stale `layer_data` ref
  - `record` — REC-011 gains a scenario
- Affected changes (MODIFIED files in `openspec/changes/`):
  - `add-component-boundary` — spec folder renamed, MODIFIED deltas added
  - `add-confidence-scoring` — formula + threshold fixed, dependency added
  - `add-provenance-explainability` — spec folder renamed
  - `add-runtime-feedback` — spec folder renamed, flaky scenario moved
  - `add-safety-invariants` — spec folder renamed, MODIFIED deltas added
  - `implement-coverage-layer` — REC-011 scenario added
- `openspec/project.md` (MODIFIED References section)
- Dependencies: nothing — this is strictly a spec cleanup, no code changes