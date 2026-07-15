# Change: Add Component Boundary — Per-Component Indices and Bottom-Up Resolution

> **Status (two-layer architecture): KEEP — Essential for monorepo support.**
> This proposal is not superseded. Testimonial.jl's primary deployment context
> is Julia monorepos with 10+ packages; per-component indices are required for
> that to work. Phase 1 ships single-package only; this proposal deploys after
> that foundation is proven. Under adapter mode, testaruda's single-store
> architecture also needs a monorepo answer — coordination between Testimonial.jl's
> component boundary and testaruda's store is an open design question (see
> Decision 5 in the Phase 1 design).

## Why

Testimonial.jl's target deployment is Julia monorepos with 10+ packages. The current `CoverageIndex` is flat — a single `Dict{String, Dict{Int, Vector{TestItemRef}}}` with no component boundary. This means:

1. Re-recording one component requires scanning everything (even if the index is per-component).
2. A change in package A selects tests in package B even if the dependency is indirect and irrelevant.
3. There's no caching — every `smart_run` recomputes the full selection.
4. CI sharding is manual: you can't say "only run tests for component A."

A component boundary makes the index compositional, cacheable, and parallelizable.

## What Changes

- **Add component identity to the data model**: `TestItemRef` gains a `component` field; `CoverageIndex` becomes per-component.
- **Add inter-component edges**: when a test in component A depends on code in component B, that's a cross-component edge.
- **Add bottom-up resolution**: on a change, resolve affected components first, then select within them (testaruda TIA-COMP-003).
- **Add cached selection decisions**: per-component cache keyed on dependency fingerprint.
- **Add parallel per-component selection**: each component's query runs concurrently.
- **Add shard plan output**: emit a balanced shard plan for CI runners.

**Relations to Phase 1**: The `CoverageIndex` struct already exists — this adds a `component` field and splits the index. The `smart_run` orchestration already has a loop — this parallelizes it per component.

## Impact

- Affected capabilities: `coverage-index` (MODIFIED data model), `recording` (MODIFIED per-component recording), `smart-selection` (MODIFIED query and orchestration), `ci-integration` (ADDED shard plan)
- New capabilities proposed: `component-architecture`
- Dependencies: `implement-coverage-layer` (needs working index)