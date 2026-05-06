# Change: Implement Phase 1 MVP — Coverage Layer

## Why

Testimonial.jl needs its core engine: the ability to record which `@testitem`s
exercise which source lines, persist that mapping as a `CoverageIndex`, and
use it to select only the impacted tests when a PR changes code. Without this,
the package does nothing. Phase 1 establishes the foundation that inference
and static layers will extend in later phases.

## What Changes

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
- Add `Orchestrator` (`smart_run`) to orchestrate git diff → query → test execution.
- Add `Inspector` for diagnostic APIs (`explain`, `index_info`).
- Expose the public API in the main `Testimonial.jl` module.
## Impact

- Affected specs: `coverage-index` (new), `recording` (new), `smart-selection` (new)
- Affected code: `src/` (all new files per the package structure in the spec)
- No breaking changes — this is greenfield
