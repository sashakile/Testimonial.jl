# Design: Phase 1 Coverage Layer + Protocol Adapter

## Context

Testimonial.jl needs to attribute code coverage to individual `@testitem`s,
not to packages or test files as a whole. Julia's LLVM-managed coverage
counters accumulate globally and — as of Julia 1.10 — cannot be reset within
a process. (Julia 1.11 introduced `Base.reset_coverage()`, which may change
this, but has not been validated experimentally for per-test attribution.
See the "Per-item subprocess isolation" decision below.) Each test item must
run in its own subprocess. This is the foundational constraint that shapes
the entire architecture.

### Two-Layer Architecture

Testimonial.jl operates in two deployment modes sharing the same core:

```
┌─────────────────────────────────────────────────┐
│  Layer 2: Protocol Layer (testimonial adapter)   │ ← stdin/stdout JSON
│  Thin entry point: run_adapter_protocol()        │    spawned by testaruda
│  Maps: discover → ASTParser                      │
│        ingest   → CoverageLayer.record_item      │
│        static-deps → Query.query                 │
│        fingerprint → file hash                   │
│        run-args   → ReTestItems.runtests args    │
├─────────────────────────────────────────────────┤
│  Layer 1: Julia Core                             │
│  Types, Persistence, ASTParser, GitDiff,         │
│  CoverageLayer, IndexBuilder, Query,             │
│  CLI (testimonial record / run / explain / gaps) │
│  Conservative fallback: run all on staleness     │
└─────────────────────────────────────────────────┘
```

The core is independently useful. The protocol layer reuses the same
internals without duplicating orchestration logic.

## Goals / Non-Goals

- **Goals:** Implement the coverage layer end-to-end. The result should be
  a working `testimonial run` that selects tests based on line-level coverage
  data, and a working `testimonial adapter` that speaks testaruda's protocol.
- **Non-Goals:** Inference layer (`@snoopi_deep`), static layer (JET),
  CI workflow files, confidence scoring, provenance chains, component
  boundary (Phase 1 ships single-package-only). Those are Phases 2–4.

## Module Architecture

To prevent the emergence of God Modules and maintain a clean dependency graph (DAG), the implementation is structured into focused modules:

| Module | Responsibility | Layer | Primary Dependencies |
|---|---|---|---|
| `src/Types.jl` | Core data structures and enums (`TestItemRef`, `CoverageIndex`, `ImpactResult`). | Core | None (Stable foundation) |
| `src/Persistence.jl` | Serialization and atomic disk I/O for index and records. | Core | `Types.jl`, `Serialization` |
| `src/ASTParser.jl` | Static discovery of `@testitem` blocks and metadata extraction. | Core | `Types.jl` |
| `src/GitDiff.jl` | Git command execution and unified diff parsing. | Core | None |
| `src/CoverageLayer.jl`| Subprocess recording orchestration and `.jl.cov` parsing. | Core | `Types.jl` |
| `src/Query.jl` | Impact analysis and coverage gap detection logic. | Core | `Types.jl` |
| `src/IndexBuilder.jl` | High-level `record_all` orchestration and index construction. | Core | `Types.jl`, `Persistence.jl`, `ASTParser.jl`, `CoverageLayer.jl` |
| `src/CLI.jl` | Standalone CLI entry points (`record`, `run`, `explain`, `gaps`).
  Re-exported as `Testimonial.run`, `Testimonial.record_all`, etc. | Core | All core modules |
| `src/Protocol.jl` | testaruda adapter protocol (`run_adapter_protocol()`). | Protocol | Core modules (no Persistence or GitDiff) |
| `src/Testimonial.jl` | Main entry point; re-exports public API. | Core | All modules |

**Not built in Phase 1:**
- `src/Orchestrator.jl` — replaced by the simplified `CLI.run` pipeline
  (`diff → query → runtests`, no policy layer)
- `src/Inspector.jl` — `explain` and `gaps` are lightweight functions in `CLI.jl`

This structure ensures that the data model is isolated from recording logic,
the protocol layer is a thin shim over the same core, and neither orchestration
nor inspection require their own modules in Phase 1.

## Decisions

see the correct test file path and item name
- **AND** the mock SHALL NOT execute any external process

### Decision: Per-item subprocess isolation
Each `@testitem` is recorded in a separate `julia --code-coverage=user`
subprocess. Julia 1.11 introduced `Base.reset_coverage()`, which may allow
in-process coverage counter resets, but this has not been validated
experimentally for per-test attribution. Inference state (Phase 2) cannot
be reset in-process regardless, making subprocess isolation the safe
default. To avoid `.jl.cov` file contention during parallel recording,
each subprocess SHALL run within a unique temporary directory containing a
symlinked shadow tree of the repository. The system SHALL ensure that the
subprocess working directory is the root of this shadow tree so that relative
paths in the test environment resolve correctly.

### Decision: Trait-based runner for testability
The system SHALL decouple subprocess command construction from execution
using a trait-based runner interface. This ensures the recording logic
is testable via mock runners without spawning actual processes in unit tests.

### Decision: TestimonialRunner as workspace member
`scripts/TestimonialRunner/` is a separate Julia workspace member containing
only the dependencies needed for recording. It depends on the root
`Testimonial` package via `pkg"dev ."` to ensure it always uses the local
source while maintaining environment isolation.

**Alternatives considered:**
- In-process coverage reset: not possible — LLVM counters are global and there
  is no Julia API to zero them mid-process. (Julia 1.11 introduced
  `Base.reset_coverage()`, which may change this, but has not been validated
  experimentally for per-test attribution. Subprocess isolation is the safe
  default until the spike in `03-risks-and-open-questions.md` is resolved.)
- Package-level coverage: too coarse; would force re-running every downstream
  test on any change.
- Sequential recording: safe but too slow for large monorepos.

### Decision: Dual-indexed `CoverageIndex` with path normalization
The index stores both `line_to_tests` (forward: source line → tests) and
`test_to_lines` (reverse: test → source lines). All paths are normalized
via `realpath` before storage to ensure consistency across different
entry points and environments.

### Decision: Item identity and ghost record prevention
A `TestItemRef` is uniquely identified by the pair `(realpath(test_file), item_name)`.
During index construction, the system only loads per-item records that
match items discovered in the current scan, preventing "ghost" records
from renamed or deleted tests from polluting the index.

### Decision: Serialization format for persistence
Index stored as `.testimonial/index.jls` using Julia's built-in `Serialization`
module. Per-item records stored in `.testimonial/items/<key>.jls`.

**Alternatives considered:**
- JSON: human-readable but large for dense coverage data and requires a
  serialization schema for nested structures.
- HDF5 / Arrow: overkill for the data volume; adds non-standard dependencies.
- `Serialization` is zero-dependency and handles Julia types directly. The
  `schema_version` field handles breaking changes.

### Decision: `schema_version` field in `CoverageIndex`
Any breaking change to `CoverageIndex` bumps `SCHEMA_VERSION`. On load, if
`index.schema_version != SCHEMA_VERSION`, the index is treated as stale and
recording is re-triggered. This allows safe evolution of the data model.

### Decision: Parallelism via `Threads.@threads`
Recording is embarrassingly parallel. We use `Threads.@threads` over the item
list with `nthreads = CPU_THREADS ÷ 2` to leave headroom for the spawned
subprocesses. This avoids needing an external job scheduler.

### Decision: Per-item cache keyed on test file hash
Cache key = `sha256(test_file_contents)[:12] * "_" * item_name`. If the key is in
`.testimonial/items/`, recording is skipped. This is the incremental recording
mechanism for Phase 1. (Finer-grained source-file invalidation is a Phase 2
concern.)

### Decision: Conservative fallback, no policy layer
The standalone CLI's `testimonial run <ref-range>` implements:
1. Load or detect missing/stale index → emit warning, run everything.
2. Parse git diff (`GitDiff.parse_unified_diff`).
3. Query index (`Query.query`).
4. Invoke `ReTestItems.runtests` on the selected items.
5. If index is stale OR if any changed line has no coverage → run everything.

No `GapPolicy` strategy pattern, no `FailPolicy`/`FallbackFastPolicy`, no
`DEFAULT_MAX_SELECTED_ITEMS` cap, no stale index warning beyond the single
"index is stale — running full suite" message. The safety is in the
over-inclusive fallback (run more, not less), which is simpler and harder
to get wrong than a policy layer.

This decision is revisited if and when `add-safety-invariants` deploys its
conservative fallback core — at that point the simple "run everything" can
be replaced by a more precise always-run set without changing the CLI API.

### Decision: Protocol adapter as a separate entry point
`Testimonial.run_adapter_protocol()` reads JSON commands from stdin and
writes JSON responses to stdout. It is wrapped in a thin shell script
(`bin/testaruda_adapter.jl`) that `testaruda.toml` points to:

```toml
[adapters]
".jl" = "julia --project=. bin/testaruda_adapter.jl"
```

The adapter reuses core functions but does NOT depend on `Persistence.jl` or
`GitDiff.jl` — testaruda's SQLite store is the system of record, and
testaruda's core handles diff parsing. The adapter is read-only with respect
to the local CoverageIndex.

### Decision: `ingest` vs. `record_all` — separate paths for adapter vs. standalone
The adapter's `ingest` handler uses `CoverageLayer.record_item` to record
specific items and returns edges inline in the `ingest` response. The
standalone `testimonial record` uses `IndexBuilder.record_all` to build
the full CoverageIndex and persist it. These are different functions that
share the same underlying recording machinery:

- `record_item(ref, runner)` — record one item, return `ItemCoverage` or
  `nothing` on failure. The `runner` parameter allows injecting a mock for
  testing. Used by both paths.
- `record_all(items, runner)` — record all items, build CoverageIndex, persist.
  The `runner` parameter allows injecting a mock for testing. Used only by
  standalone mode.
- The adapter calls `record_item` for each item in the `ingest` request,
  constructs edge data from the results, and returns it inline. No
  CoverageIndex is built or persisted.

### Decision: Cold start handling
When no CoverageIndex exists (first run, or after `rm -rf .testimonial/`):
- **Standalone mode:** `testimonial run` emits "No coverage index found —
  run `testimonial record` first to enable selective runs" and runs the
  full test suite.
- **Adapter mode:** `static-deps` returns every changed file → `unresolved`
  (testaruda's existing `TIA-SAFE-004` fallback kicks in, scheduling a full
  run). No special handling needed.

### Decision: Extensible Query Pipeline via Composite Strategy
The impact query engine and `CoverageIndex` are designed for extensibility to
support Phase 2 (Inference) and Phase 3 (Static).
- `CoverageIndex` stores layer-specific data in an extensible `layer_data::Dict{Symbol, Any}` map, avoiding a God Struct.
- `Query.jl` acts as a composite that aggregates results from a list of `ImpactProvider`s. Phase 1 implements and registers only `CoverageProvider`.

## Risks / Trade-offs

- **Subprocess startup cost:** Each item spawns a Julia subprocess (~3–10 s
  per item on warm precompilation). Mitigation: parallelism and caching mean
  most items are skipped on incremental runs.
- **Serialization portability:** `.jls` files are not portable across Julia
  versions. Mitigation: `julia_version` field in `CoverageIndex`; index is
  treated as stale on Julia upgrade.
- **Path absoluteness:** Absolute paths in the index mean it isn't portable
  across machines. This is acceptable because CI always runs from the same
  paths and local users regenerate the index.
- **Dual-store divergence:** If a user runs both standalone mode (builds local
  CoverageIndex) and adapter mode (writes to testaruda's SQLite store), the
  two stores can diverge. Mitigation: documented in project.md as a constraint;
  the adapter is explicitly read-only with respect to the local index.
- **No monorepo scoping:** Phase 1 ships single-package support only. Cross-
  package edges in a monorepo require `add-component-boundary`. Without it,
  a change in Package A that affects Package B's tests will miss the edge in
  standalone mode. The fallback (run everything) covers this gap conservatively.
  Adapter mode has the same gap — testaruda's single-store architecture is
  also single-package by default.

## Open Questions

- Should `record_all` accept a `filter` argument to subset items by tag or
  package? Useful for re-recording only one package after a targeted change.
  (Not in Phase 1 scope — defer to Phase 2.)
- What is the max `.testimonial/items/` cache size before old records should
  be pruned? (Operationally minor — defer to Phase 2.)
- The `testimonial run` CLI uses a conservative "run all on staleness"
  fallback. Does this need a `--force` flag to bypass the check? (Defer
  until someone asks for it.)