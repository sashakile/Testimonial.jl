## Context

The current safety model in `implement-coverage-layer` consists of:
1. `FallbackFastPolicy` (on coverage gaps, add `:fast`-tagged tests)
2. `FailPolicy` (on coverage gaps, raise error)
3. Max selection cap (`DEFAULT_MAX_SELECTED_ITEMS = 200`)
4. Stale index warning (24-hour threshold)

These are useful but insufficient. Key gaps:
- No guarantee that selection is a **sound over-approximation** — the spec never says "a test that SHOULD be selected MUST be selected"
- No always-run set: failed tests are forgotten until the next full recording
- No mechanism to learn from false negatives
- No support for user-defined forced-selection rules
- No verification mechanism before trusting the tool in CI

## Goals / Non-Goals

**Goals:**
- Formal soundness invariant as a spec-level contract
- Always-run set (failed, new, unrecorded, quarantined tests always selected)
- Scoped fallback (per-component, not global)
- Must-run rules (user-defined glob → test tags)
- Missed-selection incident recording and automatic edge creation
- Flaky detection and quarantine semantics
- Shadow mode: compute selections but don't gate; log divergences
- Full-run reconciliation: scheduled full runs verify past selection correctness
- Seeded-fault recall test: inject regressions, verify selection catches them
- Promotion protocol: clear criteria for advancing from shadow to enforcing

**Non-Goals:**
- Confidence scoring (→ separate proposal `add-confidence-scoring`)
- Automated promotion (human-in-the-loop)
- A/B testing between selection strategies (future work)

## Decisions

### Decision 1: Always-run set as input fact, not selection derivation
The always-run set is added as input facts to the selection relation, not derived by the query engine. This matches testaruda's TIA-ARCH-003 exclusion for always-run: it's a union operation, not a homomorphic image of the dependency graph.

### Decision 2: Scoped fallback, not global
If confidence drops below threshold or files go unresolved, only the affected component falls back to a full run. Unaffected components keep using selected subsets. This is critical for monorepos with 10+ packages (the target deployment context).

**Before `add-component-boundary` exists:** scoped fallback degrades to global fallback (all components fall back).

### Decision 3: Missed-selection incidents are candidates, not automatic edges
When a full run reveals a test failure that the most recent selection would have skipped, the system records a *candidate* incident. The incident is promoted to a permanent `manual` edge only after confirmation — either human review, or the same failure is observed across multiple independent changes. This prevents flaky or unrelated failures from creating false edges.

### Decision 4: Flaky detection on inconsistent outcomes
A test with differing pass/fail across retries in a single run is marked flaky. Quarantined tests are still selected and run (no skipping), but their outcome is excluded from pass/fail trust calculations.

### Decision 5: Shadow mode is a flag on smart_run, not a separate command
`smart_run(shadow=true)` computes selection metadata but calls `ReTestItems.runtests` on the full suite. The selection results are logged and compared against full-run outcomes post-hoc. This keeps the API surface small.

### Decision 6: Reconciliation runs as a separate CI workflow
Full-run reconciliation is a scheduled workflow (nightly) that runs all tests, computes the counterfactual selection, and records any incidents. It's not part of the per-PR `smart_run` to avoid latency overhead.

### Decision 7: Seeded-fault test is a diagnostic script, not part of smart_run
A `scripts/seeded_fault_test.jl` that: (1) introduces a known regression (e.g., swaps a function body), (2) runs selection, (3) verifies the regression-revealing test is selected. Exit code is non-zero if any fault's revealing test is missed. Run as a pre-deployment check in CI.

### Decision 8: Promotion requires shadow mode, not just green suite
The evaluation window runs in shadow mode, which runs all tests regardless of selection. The metric is: "would a failing test have been selected?" — not "did any test fail?" This avoids conflating selection correctness with test suite health.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Always-run set grows unboundedly if many tests fail | Cap on always-run size with logging; stale entries evicted after N passes |
| Manual edges accumulate over time | Deduplication by (content_unit, test) pair; periodic cleanup of stale edges (N passes without triggering) |
| Scoped fallback increases complexity in CI reporting | Each scope reports its fallback reason independently |
| Flaky detection is heuristic | Publish the heuristic alongside test output; user can override with `tags=[:flaky]` |
| Shadow mode doubles CI runtime | It's temporary; the team disables it after the zero-incident window completes |
| Seeded faults accidentally merged | Seeds are generated and reverted in the same script; CI runs in a temp workspace |
| Zero-incident window is too long or short | Configurable window size (default: 7 days or 100 PRs, whichever comes first) |

## Open Questions

- Should always-run eviction be time-based (X days) or pass-count–based (X consecutive passes)?
- Should must-run rules support negative patterns (exclude globs)?
- Should the reconciliation workflow auto-file a CI issue on incident detection?
- Should promotion be automatic or require a manual config change?