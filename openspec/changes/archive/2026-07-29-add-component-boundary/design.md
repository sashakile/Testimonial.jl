## Context

Current data model:
- `TestItemRef`: `(test_file, item_name, tags, file_hash)`
- `CoverageIndex`: single global map

After this change:
- `TestItemRef`: `(component, test_file, item_name, tags, file_hash)` — component is the first identity field
- `CoverageIndex`: per-component, with an additional `inter_component_edges` map
- `ComponentGraph`: separate from the fine-grained index, stores which components depend on which

## Goals / Non-Goals

**Goals:**
- Component-scoped indices stored under `.testimonial/components/<name>/`
- Inter-component edges (component A test → component B content unit)
- Bottom-up component resolution (resolve affected components, then select within them)
- Per-component cached selection decisions keyed on dependency fingerprint
- Parallel per-component selection via `Threads.@threads`
- Duration-balanced shard plan for CI

**Non-Goals:**
- Multi-repo cross-component (out of scope; this is monorepo only)
- Remote cache sharing (separate proposal)
- Symbol-level inter-component edges (file-level is sufficient for Phase 1)

## Decisions

### Decision 1: Component identified by workspace package name
In a Julia workspace monorepo, the component name is the package name from `[workspace]` in `Project.toml`. The workspace file already lists all packages — Testimonial.jl reads this to discover components.

### Decision 2: Inter-component edges at file level, not line level
Cross-component dependencies are recorded as "component A's test(s) depend on component B's file(s)," not "line 42 in file X." This coarser granularity is sufficient for bottom-up resolution and avoids combinatorial complexity.

### Decision 3: Cache key = dependency fingerprint
A component's cached selection is valid if its dependency fingerprint (hash of all content units it depends on + environment) is unchanged. If the fingerprint changes, only that component re-selection is needed.

### Decision 4: Shard plan from recorded durations
Tests in the selected set are assigned to shards using a greedy duration-balancing algorithm (sort by descending mean duration, assign each to the currently lightest shard). This matches testaruda's TIA-COMP-012 approach.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Component auto-detection misses some packages | Support explicit `components` list in `Testimonial.toml` as override |
| Inter-component edges are coarse (file-level) | Acceptable for monorepo scale; refine to symbol-level if false positives become problematic |
| Cache invalidation is conservative (re-selects on any fingerprint change) | Conservative is correct per soundness invariant; refinement is future work |
| Shard plan assumes homogenous runners | Support per-shard weighting via config |

## Open Questions

- Should component identity be inferred from workspace metadata or declared explicitly?
- Should inter-component edges be stored in the source component's index or a shared global map?