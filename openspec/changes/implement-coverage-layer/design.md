# Design: Phase 1 Coverage Layer

## Context

Testimonial.jl needs to attribute code coverage to individual `@testitem`s,
not to packages or test files as a whole. Julia's LLVM-managed coverage
counters accumulate globally and cannot be reset within a process, so each
test item must run in its own subprocess. This is the foundational constraint
that shapes the entire architecture.

## Goals / Non-Goals

- **Goals:** Implement the coverage layer end-to-end. The result should be
  a working `smart_run` that selects tests based on line-level coverage data.
- **Non-Goals:** Inference layer (`@snoopi_deep`), static layer (JET), CLI
  binary, CI workflow files. Those are Phases 2–4.

## Decisions

### Decision: Per-item subprocess isolation
Each `@testitem` is recorded in a separate `julia --code-coverage=user`
subprocess. The subprocess runs `ReTestItems.runtests` filtered to exactly one
item, producing `.jl.cov` sidecar files that are then parsed by `Coverage.jl`.

**Alternatives considered:**
- In-process coverage reset: not possible — LLVM counters are global and there
  is no Julia API to zero them mid-process.
- Package-level coverage: too coarse; would force re-running every downstream
  test on any change.

### Decision: Dual-indexed `CoverageIndex`
The index stores both `line_to_tests` (forward: source line → tests) and
`test_to_lines` (reverse: test → source lines). The forward index answers
impact queries in O(changed lines). The reverse index enables incremental
re-recording (skip items whose covered files haven't changed) and the
`explain` API.

**Alternatives considered:**
- Forward-only index: faster to build, but `explain` and incremental recording
  require a full scan. Rejected given the intended scale (~500 items).

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

### Decision: Coverage gap policy
When changed lines have no recorded coverage in any layer, `smart_run` falls
back to running the `:fast` tag suite by default (`strict_coverage=false`).
With `strict_coverage=true`, it fails with an explanatory message. Phase 1
hardcodes these two behaviors; Phase 3 will generalize them into the
`on_coverage_gap` config key (`"fallback_fast"` / `"fail"` / `"warn"`).

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

## Open Questions

- Should `record_all` accept a `filter` argument to subset items by tag or
  package? Useful for re-recording only one package after a targeted change.
  (Not in Phase 1 scope — defer to Phase 2.)
- What is the max `.testimonial/items/` cache size before old records should
  be pruned? (Operationally minor — defer to configuration work in Phase 3.)
