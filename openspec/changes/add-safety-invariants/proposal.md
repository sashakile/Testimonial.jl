# Change: Add Safety Invariants — Soundness Guarantee, Always-Run Set, Fallback Architecture, and Verification Protocol

## Why

Testimonial.jl has no formal soundness guarantee. If a test is missed by selection, that's a silent CI gap with no detection mechanism. The current `FallbackFastPolicy` and `strict_coverage` are ad-hoc responses, not a coherent safety architecture. Without explicit invariants, confidence in the tool erodes over time as edge cases surface.

Furthermore, there is no way to validate correctness before trusting the selection in CI. Deploying `smart_run` as a CI gate without verification is a leap of faith.

## What Changes

- **Add a soundness invariant**: the selection MUST over-approximate the true affected set (missed selection = bug).
- **Add an always-run set**: tests that failed last run, newly added tests, tests with no history, and quarantined tests are unconditionally selected.
- **Add scoped fallback policies**: per-component fallback on unresolved files, environment changes, unknown file kinds — not a global "run everything" fallback.
- **Add missed-selection incident recording**: when a full run reveals a test that selection would have skipped, record a candidate incident; promote to a manual edge after confirmation.
- **Add must-run rules**: user-defined path glob → forced test selection.
- **Add flaky detection and quarantine semantics**.
- **Add periodic full-run reconciliation**: scheduled full runs compare their results against the counterfactual selection, detecting missed-selection incidents.
- **Add shadow mode**: `smart_run` computes the selection but runs all tests, logging what would have been skipped. Selection results are compared against full-run outcomes.
- **Add seeded-fault recall test**: inject known regressions into the repo, verify the fault-revealing test is selected. Used as a pre-deployment gate.
- **Add promotion protocol**: shadow mode → zero-missed-selection window → enforcing mode. Only after proving correctness does the tool gate CI.

**Relations to Phase 1**: The always-run set is implementable immediately (it's just metadata + a union). Soundness invariant is a design contract, not code. Fallback policies slot into `smart_run`'s `GapPolicy` dispatch. Missed-selection recording and shadow mode require `add-runtime-feedback` (ingest).

## Impact

- Affected capabilities: `smart-selection` (MODIFIED `smart_run` orchestration), `ci-integration` (ADDED incident detection, reconciliation pipeline)
- New capabilities proposed: `safety-invariants`
- Dependencies: `implement-coverage-layer` (needs working recording + selection), `add-runtime-feedback` (for missed-selection recording and ingest), `add-component-boundary` (for scoped fallback; degrades to global fallback before component boundary exists)