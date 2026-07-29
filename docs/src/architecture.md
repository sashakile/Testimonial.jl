# Architecture

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

## Module Structure

| Module | Responsibility |
|--------|---------------|
| `Testimonial.jl` | Main entry point, type definitions, public API |
| `CLI.jl` | User-facing commands (record, run, explain, gaps) |
| `CoverageLayer.jl` | Subprocess recording orchestration, `.jl.cov` parsing |
| `IndexBuilder.jl` | Index construction, per-component persistence, migration |
| `Query.jl` | Impact analysis, coverage gap detection |
| `GitDiff.jl` | Unified diff parsing |
| `Protocol.jl` | testaruda adapter protocol handlers |

## Key Design Decisions

- **Per-item subprocess isolation** — Julia's coverage counters cannot be
  reset in-process, so each `@testitem` runs in its own subprocess
- **Dual-indexed CoverageIndex** — `line_to_tests` + `test_to_lines` for
  fast queries in both directions
- **Serialization-based persistence** — `.jls` format with `schema_version`
  for safe evolution
- **Conservative fallback** — run everything on staleness, gaps, or missing index