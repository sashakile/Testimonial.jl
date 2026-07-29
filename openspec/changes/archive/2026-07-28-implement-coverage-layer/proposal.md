# Change: Implement Phase 1 MVP — Coverage Layer + Protocol Adapter

## Why

Testimonial.jl needs its core engine: the ability to record which `@testitem`s
exercise which source lines, persist that mapping as a `CoverageIndex`, and
use it to select only the impacted tests when a PR changes code. Without this,
the package does nothing.

Phase 1 establishes the foundation that inference and static layers will
extend in later phases. It also establishes the **two-layer architecture**:
the Julia core works standalone (`testimonial record` → `testimonial run`),
and a thin protocol layer speaks testaruda's adapter protocol for users who
want a language-agnostic orchestrator with SQLite persistence, confidence
scoring, and safety invariants provided by testaruda's Rust core.

## What Changes

### Layer 1 — Julia Core

- Add the `CoverageIndex` and `TestItemRef` data model with Serialization-based
  persistence. Logic split across `Types.jl` (data), `Persistence.jl` (disk),
  and `IndexBuilder.jl` (construction).
- Add `ImpactResult` / `ImpactReason` (why a test was selected) and
  `CoverageGap` (uncovered changed lines) value types in `Types.jl`.
- Add `ASTParser` to discover `@testitem` blocks in Julia source files.
- Add `GitDiff` to parse unified diffs into `Dict{String, Set{Int}}` (file →
  changed lines).
- Add `CoverageLayer` to drive per-item subprocess recording
  (`--code-coverage=user`) and parse `.jl.cov` sidecar files.
- Add `Query` to look up impacted test items and detect coverage gaps.
- Add a minimal CLI entry point: `testimonial record` (build index),
  `testimonial run <ref-range>` (diff → query → runtests), `testimonial explain`
  (inspect selection), `testimonial gaps` (report uncovered lines).
- **Conservative fallback in standalone mode:** if no index exists or it's
  stale, run the full test suite. No gap policies, no confidence thresholds,
  no promotion protocol. The safety is in the over-inclusive fallback.
- The old `Orchestrator.jl` (`smart_run` with policy layers) is **not built**.
  The standalone `run` command is a straight pipeline: `diff → query → runtests`.
  `Inspector.jl` is also deferred — `explain` and `gaps` are lightweight
  functions in the CLI, not a separate module.

### Layer 2 — Protocol Adapter

- Add `Testimonial.run_adapter_protocol()` — a thin entry point that reads
  one JSON command per line from stdin and writes one JSON response per line
  to stdout, per testaruda's `TIA-ADAPT-001` protocol.
- The adapter reuses the same core functions: `ASTParser.discover_testitems`
  for `discover`, `CoverageLayer.record_item` for `ingest`, `Query.query`
  for `static-deps`, file hashing for `fingerprint`, and `ReTestItems.runtests`
  args for `run-args`.
- The adapter is **read-only** with respect to the local `CoverageIndex` —
  coverage data goes to testaruda's SQLite store via the `ingest` response.
- The adapter entry point is a `bin/testaruda_adapter.jl` script (or
  `julia -e 'using Testimonial; Testimonial.run_adapter_protocol()'`),
  pointed to by `testaruda.toml`.

### What's dropped from earlier spec

- **No `Orchestrator.jl`** — the standalone `smart_run` pipeline is
  simplified to a direct `diff → query → runtests` with no gap policies,
  no confidence thresholds, no max-selection cap.
- **No `Inspector.jl`** — `explain` and `gaps` are lightweight CLI functions,
  not a separate module.
- **No `smart-selection` policy layer** — `GapPolicy`, `FallbackFastPolicy`,
  `FailPolicy`, stale index warning, staleness checks are not built. The
  fallback is: if index is stale/missing, run everything.

## Impact

- Affected specs: `coverage-index` (new), `recording` (new), `smart-selection`
  (new, simplified), `protocol-adapter` (new)
- Affected code: `src/` (all new files per the module structure in the spec)
- No breaking changes — this is greenfield