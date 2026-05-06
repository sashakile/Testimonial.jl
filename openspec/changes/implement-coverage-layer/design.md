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

## Module Architecture

To prevent the emergence of God Modules and maintain a clean dependency graph (DAG), the implementation is structured into focused modules:

| Module | Responsibility | Primary Dependencies |
|---|---|---|
| `src/Types.jl` | Core data structures and enums (`TestItemRef`, `CoverageIndex`, `ImpactResult`). | None (Stable foundation) |
| `src/Persistence.jl` | Serialization and atomic disk I/O for index and records. | `Types.jl`, `Serialization` |
| `src/ASTParser.jl` | Static discovery of `@testitem` blocks and metadata extraction. | `Types.jl` |
| `src/GitDiff.jl` | Git command execution and unified diff parsing. | None |
| `src/CoverageLayer.jl`| Subprocess recording orchestration and `.jl.cov` parsing. | `Types.jl` |
| `src/Query.jl` | Impact analysis and coverage gap detection logic. | `Types.jl` |
| `src/IndexBuilder.jl` | High-level `record_all` orchestration and index construction. | `Types.jl`, `Persistence.jl`, `ASTParser.jl`, `CoverageLayer.jl` |
| `src/Orchestrator.jl` | `smart_run` pipeline (diff → query → policy → execution). | `Types.jl`, `GitDiff.jl`, `Query.jl`, `Persistence.jl` |
| `src/Inspector.jl` | Public inspection APIs (`explain`, `index_info`). | `Types.jl`, `Persistence.jl` |
| `src/Testimonial.jl` | Main entry point; re-exports public API. | All modules |

This structure ensures that the data model is isolated from recording logic, and the orchestration pipeline is separated from inspection tools, allowing for independent testing and evolution of each component.

## Decisions

### Decision: Per-item subprocess isolation
Each `@testitem` is recorded in a separate `julia --code-coverage=user`
subprocess. To avoid `.jl.cov` file contention during parallel recording,
each subprocess runs in a unique temporary directory where the project
root is symlinked (or used as a base). The subprocess runs `ReTestItems.runtests`
filtered by BOTH file path and item name to avoid name collisions.

**Alternatives considered:**
- In-process coverage reset: not possible — LLVM counters are global and there
  is no Julia API to zero them mid-process.
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

### Decision: Coverage gap policy via Strategy Pattern
When changed lines have no recorded coverage in any layer, `smart_run` handles the gap
using a `GapPolicy` strategy. We define `abstract type GapPolicy end` with concrete
implementations like `FallbackFastPolicy` (default, runs `:fast` tag) and `FailPolicy`
(raises an error with missing lines). This isolates policy logic from the orchestrator
and allows easy injection of custom policies in Phase 3.

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

## Open Questions

- Should `record_all` accept a `filter` argument to subset items by tag or
  package? Useful for re-recording only one package after a targeted change.
  (Not in Phase 1 scope — defer to Phase 2.)
- What is the max `.testimonial/items/` cache size before old records should
  be pruned? (Operationally minor — defer to configuration work in Phase 3.)
