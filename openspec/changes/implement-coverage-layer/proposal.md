# Change: Implement Phase 1 MVP — Coverage Layer

## Why

Testimonial.jl needs its core engine: the ability to record which `@testitem`s
exercise which source lines, persist that mapping as a `CoverageIndex`, and
use it to select only the impacted tests when a PR changes code. Without this,
the package does nothing. Phase 1 establishes the foundation that inference
and static layers will extend in later phases.

## What Changes

- Add the `CoverageIndex` and `TestItemRef` data model with Serialization-based
  persistence at `.testimonial/index.jls`.
- Add `ImpactResult` / `ImpactReason` (why a test was selected) and
  `CoverageGap` (uncovered changed lines) value types.
- Add `ASTParser` to discover `@testitem` blocks in Julia source files.
- Add `GitDiff` to parse unified diffs into `Dict{String, Set{Int}}` (file →
  changed lines).
- Add `CoverageLayer` to drive per-item subprocess recording
  (`--code-coverage=user`) and parse `.jl.cov` sidecar files.
- Add `Index` to build and persist the `CoverageIndex` from per-item records.
- Add `Query` to look up impacted test items and detect coverage gaps.
- Add `Runner` (`smart_run`) to orchestrate git diff → query → test execution.
- Expose the public API (`record_all`, `record_item`, `query`, `query_files`,
  `smart_run`, `explain`, `coverage_gaps`, `index_info`) in `Testimonial.jl`.

## Impact

- Affected specs: `coverage-index` (new), `recording` (new), `smart-selection` (new)
- Affected code: `src/` (all new files per the package structure in the spec)
- No breaking changes — this is greenfield
