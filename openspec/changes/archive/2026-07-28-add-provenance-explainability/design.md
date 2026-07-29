## Context

Current API:
- `query(changed)` returns `Vector{ImpactResult}` — one per selected test, with flat `Vector{ImpactReason}`
- `explain(test_file, item_name)` returns `Vector{String}` — list of source files with line counts

Gaps:
- No way to ask "why was this specific test NOT selected?"
- No chain of reasoning (just "line 47" without "because line 47 is in function `foo()` which is called by `run_model()` which is a dependency of test X")
- No provenance persistence — re-explain requires re-running the full query
- No indication of which analysis layer contributed (coverage vs inference vs static)

## Goals / Non-Goals

**Goals:**
- Reason chains: for each selected test, produce the chain of edges + changed content that caused it
- Exclusion reasoning: for any non-selected test in the index, produce a reason it was excluded
- Persisted provenance: store provenance with the index so re-explanation doesn't need re-query
- Layered view: attribute each edge to its analysis layer

**Non-Goals:**
- Full why-provenance polynomial (testaruda TIA-PROV-001 uses semiring provenance; minimal-witness chains are sufficient for Phase 1)
- Minimal-witness derivation algorithm (just store the chain that was computed during query)

## Decisions

### Decision 1: Reason chains, not full provenance polynomials
Full why-provenance (enumerating all paths) is O(n^m) in the dependency graph. A single minimal-witness chain (the first path found during query) is sufficient for debugging and much cheaper to store. This matches testaruda's TIA-ENG-009.

### Decision 2: Exclusion reasons derived from the index state, not stored
Exclusion reasoning ("why was X not selected?") is computed on-demand by checking:
1. Is the test in the index? (If not: "test has never been recorded")
2. Are any of the changed files in the test's coverage footprint? (If not: "no changed file touches any covered line")
3. Has the test file itself changed? (If not: "test file unchanged")
4. For each changed line in its coverage: is that line in the changed set? (If not: "changed lines don't overlap with covered lines")

This is deterministic from the index + diff and doesn't need explicit storage.

### Decision 3: Provenance stored as sidecar alongside the index
After each `smart_run`, the provenance for that selection is stored at `.testimonial/provenance/<run_key>.jls`. This enables post-hoc explanation without re-querying. The store is pruned on a sliding window (keep last N runs).

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Reason chain storage grows with index size | Cap at one chain per selected test; prune old runs |
| Exclusion reasoning is slower than direct lookup | It's an interactive API, not a perf-critical path; O(k * n) where k=changed files, n=test coverage is acceptable |
| Developers rely on stale provenance | Timestamp each provenance record; warn if > run duration threshold |

## Open Questions

- Should reason chains be user-visible in the CLI or only via API?
- Should exclusion reasons include "suggested fix" (e.g., "test covers no lines in changed files — consider adding coverage through integration tests")?