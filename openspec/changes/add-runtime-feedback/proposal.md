# Change: Add Runtime Feedback Loop — Ingest Phase and Edge Learning

## Why

Testimonial.jl's recording is a one-way process: you record an index, then you query it. The index never learns from what actually happened when tests ran. If a test exercises code that static coverage analysis missed, that gap persists until the next full recording. A runtime feedback loop closes this gap continuously.

## What Changes

- **Add an `ingest` function** to `smart_run` — after running selected tests, feed back the actual coverage/execution data to update the index.
- **Add runtime edge creation**: when coverage shows a test touched a content unit not in its static edges, record a new runtime edge.
- **Add run history tracking**: per-test outcome, duration, failure rate, attempt count — persisted across index builds.
- **Add external input recording**: track config files, environment variables, fixtures read at runtime as dependency edges.
- **Make ingest idempotent**: each run payload carries a unique run-identity key to prevent duplicate ingestion.

**Relations to Phase 1**: The ingest phase slots into `smart_run` after `runtests` completes. The indexing machinery already exists (`ItemCoverage`, `CoverageIndex` construction) — this adds an update path instead of a full rebuild.

## Impact

- Affected capabilities: `smart-selection` (MODIFIED `smart_run` orchestration), `recording` (ADDED ingest mode), `coverage-index` (ADDED runtime edges)
- New capabilities proposed: `runtime-feedback`
- Dependencies: `implement-coverage-layer` (needs working recording + selection), `add-safety-invariants` (for flaky detection used in runtime edge exclusion)
