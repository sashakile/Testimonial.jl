## Context

Current flow: `record_all` → (`smart_run` → `query` → `runtests` → end). No feedback.

After this change: `record_all` → (`smart_run` → `query` → `runtests` → **ingest** → update index).

The ingest phase reuses the same subprocess isolation pattern as recording — coverage sidecars from the test run are parsed and merged into the index. New runtime edges are added to `inference_edges` (Phase 2, or a new `runtime_edges` field) without removing static edges.

## Goals / Non-Goals

**Goals:**
- Post-run coverage ingestion that updates the index incrementally
- Runtime edge creation (coverage-discovered dependencies)
- Run history persistence (outcome, duration, failure rate)
- Idempotent ingestion (run-identity key dedup)
- External input recording (config, env, fixtures)

**Non-Goals:**
- Missed-selection incident detection (→ `add-safety-invariants`)
- Flaky detection (→ `add-safety-invariants`)
- Confidence scoring from run history (→ `add-confidence-scoring`)

## Decisions

### Decision 1: Ingestion happens synchronously after `runtests` in `smart_run`
The ingest phase is part of `smart_run`'s post-execution step, not a separate CLI command. This avoids changing the user workflow — they still call `smart_run`, which now also learns. The caller blocks until ingestion completes, ensuring the index is always in a consistent state before the next invocation.

### Decision 2: Runtime edges never remove static edges
Static edges model potential dependencies; runtime edges confirm actual ones. Removing a static edge because runtime didn't confirm it would sacrifice recall (testaruda TIA-SEL-004 makes the same choice). Both coexist; selection is the union.

### Decision 3: Run history stored in a sidecar file, not the main index
The index is rebuilt on each recording. Run history should survive index rebuilds. Store it in `.testimonial/run_history.jls` as a `Dict{TestItemRef, RunHistoryEntry}` persisted independently from `CoverageIndex`.

### Decision 4: External inputs recorded by convention
The user annotates external inputs via `@testitem` options or `Testimonial.toml` (e.g., "this test reads `config/default.toml`"). Future work could automate this via Julia's file-open instrumentation, but Phase 1 relies on explicit declaration.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Ingestion doubles smart_run wall-clock time | Run synchronously after `runtests` exits; ingestion completes before the next invocation. If latency is a concern, use `auto_ingest=false` and run ingestion out-of-band |
| Run history grows unboundedly | Prune entries older than N days (configurable) |
| Runtime edges from flaky runs corrupt the index | Filter by test stability score; only ingest edges from non-flaky runs |
| Idempotency requires caller discipline | Reject ingestion if no run-identity key present; document requirement clearly |

## Open Questions

- Should ingest be synchronous (blocking) or async (fire-and-forget with a lock)?
- Should external inputs be declared per-test or per-component?
