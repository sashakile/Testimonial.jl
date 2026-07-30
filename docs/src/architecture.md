---
title: Architecture
description: Testimonial.jl architecture — two-layer design, module structure, data flow, and pipeline explanations
category: explanation
---

# Architecture

**TL;DR:** Testimonial operates in two deployment modes (standalone and protocol adapter) sharing the same Julia core. The core provides per-item subprocess recording, a dual-indexed coverage index, git-diff-driven query pipeline, and conservative fallback on uncertainty.

## Two-Layer Architecture

Testimonial.jl operates in two deployment modes sharing the same core:

```
┌─────────────────────────────────────────────────┐
│  Layer 2: Protocol Layer (testimonial adapter)   │ ← stdin/stdout JSON
│  Thin entry point mapping testaruda commands     │    spawned by testaruda
│  (discover, ingest, static-deps, fingerprint,    │
│   run-args) to the core below. No persistence,   │
│   no orchestration — testaruda owns those.       │
├─────────────────────────────────────────────────┤
│  Layer 1: Julia Core (standalone)                │
│  ASTParser, CoverageLayer, IndexBuilder,        │
│  CoverageIndex, Query, GitDiff, Persistence,     │
│  CLI (testimonial record, run, explain, gaps).   │
│  Minimal orchestration: query → runtests.        │
│  Conservative fallback: run all on staleness.    │
└─────────────────────────────────────────────────┘
```

The core is independently useful as a standalone tool. The protocol layer reuses the same internals without duplicating orchestration logic.

### Three Analysis Layers

Testimonial uses three complementary analysis layers for complete coverage:

| Layer | Mechanism | Primary Use |
|---|---|---|
| **Coverage** | `--code-coverage=user` | Precise line attribution (~95% of PRs) |
| **Inference** | `SnoopCompile.@snoopi_deep` | Newly added methods not yet in coverage |
| **Static** | `JET.report_package` | Abstract dispatch paths, declared entrypoints |

Layers are additive: inference and static edges never remove selections, only add them.

## Data Flow

```
Code change (git diff)
        │
        ▼
  GitDiff.parse_unified_diff()
        │
        ▼
  Changed files + lines
        │
        ▼
  Query layer ──► CoverageIndex (dual-indexed)
        │                  │
        │           line_to_tests     test_to_lines
        │           (for impact)      (for re-recording)
        │
        ▼
  Selected test items
        │
        ▼
  Safety layer ──► Always-run set, must-run rules, incidents
        │
        ▼
  Run selected tests (or all in shadow mode)
        │
        ▼
  Post-run: ingest results, update run history, reconcile
```

## Module Structure

| Module | Responsibility |
|--------|---------------|
| `Testimonial.jl` | Main entry point, type definitions, public API, run history, incidents, provenance |
| `CLI.jl` | User-facing commands (record, run, explain, gaps, incidents, index_info) |
| `CoverageLayer.jl` | Subprocess recording orchestration, `.jl.cov` and LCOV tracefile parsing |
| `IndexBuilder.jl` | Index construction, per-component persistence, migration, cache management |
| `Query.jl` | Impact analysis (direct change, dependency), coverage gap detection |
| `GitDiff.jl` | Unified diff parsing (new, deleted, renamed files) |
| `Protocol.jl` | testaruda adapter protocol handlers (discover, ingest, static-deps, fingerprint, run-args) |
| `StaticLayer.jl` | Static analysis (JET-based entrypoint analysis, abstract dispatch) |

## Recording Pipeline

```
1. Discover @testitem blocks ───► List of TestItemRefs
        │
        ▼
2. For each item, check cache ───► Is item's test file unchanged?
        │                            │
        ▼                            ▼
   Run in subprocess             Use cached coverage
        │
        ▼
3. Parse coverage sidecar (.jl.cov or LCOV)
        │
        ▼
4. Build/update CoverageIndex
   - line_to_tests: Map{source_line → Set{TestItemRef}}
   - test_to_lines: Map{TestItemRef → Set{source_line}}
```

Items are recorded in parallel via `Threads.@threads`. Each item runs in an isolated subprocess because Julia's coverage counters cannot be reset in-process.

For bulk initial recording, items sharing a test file can be batched into a single subprocess per file (amortising the ~144ms Julia startup cost), producing a safe over-approximation of per-item coverage.

## Query Pipeline

```
1. Parse git diff ───► Map{file_path → Set{changed_lines}}
        │
        ▼
2. For each changed file:
   │
   ├─ If tracked in CoverageIndex:
   │   Look up line_to_tests for changed lines
   │   └─ Return ImpactResult with DirectChange reasons
   │
   ├─ If not tracked (source file, config):
   │   └─ Return Unresolved (trigger fallback)
   │
   └─ If test file changed:
       └─ Select all items in that file
        │
        ▼
3. Apply safety layer:
   - Add always-run tests
   - Apply must-run rules
   - Check confidence thresholds
        │
        ▼
4. Return final selection
```

## Component Resolution

When component boundary is enabled, per-component indices are maintained:

```
1. Detect components from workspace Project.toml
        │
        ▼
2. Build component graph (inter-component dependencies)
        │
        ▼
3. For a change in component A:
   - Query A's index for affected tests
   - Resolve dependencies: also check B, C if A depends on them
   - Aggregate results bottom-up
        │
        ▼
4. Cache per-component selection results
   (invalidated when component fingerprint changes)
```

## Incident Lifecycle

```
1. Full run completes
        │
        ▼
2. Compare selection against actual outcomes
        │
        ▼
3. If selection missed a failure ───► Create Candidate incident
        │                                 │
        ▼                                 ▼
    No incident                      4. Same failure 3× more?
                                            │
                                            ▼
                                     Promote to manual edge
                                     (permanent selection rule)
```

## CI Artifact Flow

The coverage index is built nightly (06:00 UTC) and made available as a CI artifact:

```
Nightly workflow (main)
        │
        ├─ record_all() — full coverage recording
        ├─ upload index as CI artifact
        └─ artifact available for ~24h
        │
        ▼
PR workflow (feature branch)
        │
        ├─ download latest nightly index artifact
        ├─ parse git diff between PR and main
        ├─ run smart selection against the index
        └─ run only selected tests
```

This means the index is always at most 24h stale during normal CI operation. If no nightly index exists (e.g., first run after setup), the PR workflow falls back to running all tests.

## Key Design Decisions

- **Per-item subprocess isolation** — Julia's coverage counters cannot be reset in-process, so each `@testitem` runs in its own subprocess
- **Dual-indexed CoverageIndex** — `line_to_tests` + `test_to_lines` for fast queries in both directions
- **Serialization-based persistence** — `.jls` format with `schema_version` for safe evolution
- **Conservative fallback** — run everything on staleness, gaps, or missing index
- **Analysis layers are additive** — inference and static edges never remove selections, only add them