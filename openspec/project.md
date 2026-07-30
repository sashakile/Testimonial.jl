# Project Context

## Purpose

Testimonial.jl is a Julia-native test impact analysis engine. Given a set
of code changes (from a git diff), it selects the minimal set of `@testitem`s
that must run to validate those changes — turning a 30-minute CI test suite
into a 30-second feedback loop on most PRs.

It operates in **two deployment modes**:

1. **Standalone mode** — `testimonial run <ref-range>`: parses the git diff,
   queries the coverage index, and invokes `ReTestItems.runtests` on the
   selected items. Conservative fallback: if no index exists or it's stale,
   run everything. No policy layers beyond that.
2. **Adapter mode** — `testimonial adapter`: a thin JSON-protocol subprocess
   spawned by [testaruda](https://github.com/charly-vibes/testaruda) (a
   language-agnostic test impact analysis orchestrator). testaruda owns
   orchestration, SQLite persistence, confidence scoring, safety invariants,
   and provenance — the adapter speaks stdin/stdout JSON and delegates
   Julia-specific work (discovery, coverage recording, diff parsing) to Testimonial.jl's core.

The primary intended deployment context is Julia monorepos with 10+ packages
and hundreds of `@testitem`s (e.g., SundaeVolatility scale).

### Architecture: Two Layers

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

The core is independently useful as a standalone tool. The protocol layer
reuses the same internals without duplicating orchestration logic.

## Domain Model

The core abstraction is the **`CoverageIndex`** — a dual-indexed artifact that
maps source lines → test items (for fast impact queries) and test items →
source lines (for incremental re-recording). Recording runs each `@testitem`
in a **separate subprocess**. A spike confirmed that no in-process coverage
reset API is available (see `.wai/research/2026-07-15-reset-coverage-spike.md`).
Inference state (Phase 2)
cannot be reset in-process regardless, making subprocess isolation the safe
default for both layers. Separate processes also ensure a pristine global
state for each test.

Three analysis layers stack for complete coverage:

Three analysis layers stack for complete coverage:

| Layer | Mechanism | Primary Use |
|---|---|---|
| **Coverage** | `--code-coverage=user` | Precise line attribution (~95% of PRs) |
| **Inference** | `SnoopCompile.@snoopi_deep` | Newly added methods not yet in coverage |
| **Static** | `JET.report_package` | Abstract dispatch paths, declared entrypoints |

## Capability Specs

### Core capabilities (Layer 1 — always present)

| Capability | Purpose | Status |
|---|---|---|
| `coverage-index` | `CoverageIndex` data model, persistence (`.testimonial/index.jls`) | Active |
| `recording` | Per-item subprocess recording, parallelism, index construction | Active |
| `smart-selection` | Git diff → query pipeline, coverage gap detection, `testimonial run` | Active |
| `inference-layer` | `@snoopi_deep` capture and inference edge construction | Active (Phase 2) |
| `static-layer` | JET-based entrypoint analysis and static edge construction | Active (Phase 3) |
| `cli` | Command-line interface (`testimonial record`, `run`, `explain`, `gaps`, `incidents`) | Active |

### Adapter protocol capabilities (Layer 2 — only used when spawned by testaruda)

| Capability | Purpose | Status |
|---|---|---|
| `protocol-adapter` | JSON stdin/stdout protocol (handshake, discover, ingest, static-deps, fingerprint, run-args) | Active |

### Standalone-mode enhancements (Layer 1 extensions)

| Capability | Purpose | Status |
|---|---|---|
| `component-architecture` | Per-component indices, bottom-up resolution, cached selection | Active |
| `safety-invariants` | Soundness invariant, always-run set, shadow mode, incident detection, reconciliation | Active |
| `confidence-scoring` | Per-test confidence computation, threshold-based fallback gating | Active |
| `provenance` | Reason chains, exclusion reasoning, persisted provenance | Active |
| `runtime-feedback` | Post-run ingestion, runtime edge creation, run history | Active |
| `configuration` | `Testimonial.toml` parsing, tag overrides, selection caps | Active |
| `ci-integration` | Two-workflow pattern (recording + PR), index artifact handling | Active (nightly record + reconciliation workflows)

## Implementation Phases

Per the specification:
- **Phase 1 (MVP):** coverage layer core + standalone CLI — `Types`, `Persistence`, `ASTParser`, `GitDiff`, `CoverageLayer`, `IndexBuilder`, `Query`, `Testimonial.jl` (CLI entry points: `record`, `run`, `explain`, `gaps`). Plus the adapter protocol entry point (`testimonial adapter`).
- **Phase 2:** inference layer — `@snoopi_deep` capture and inference edges ✅
- **Phase 3:** static layer — JET entrypoint analysis, `Testimonial.toml` config ✅
- **Phases 2–3** update both the standalone CLI and the adapter protocol's `static-deps`/`ingest` handlers.

## Tech Stack

- Julia >= 1.12
- `ReTestItems.jl` — test item discovery and execution
- `Coverage.jl` — `.jl.cov` sidecar file parsing
- `SnoopCompile.jl` — inference tracing (`@snoopi_deep`)
- `JET.jl` — static call graph analysis
- `Serialization` — index persistence (`.jls` format)
- `wai` for reasoning and session continuity
- `beads` (`bd`) for issue tracking
- `openspec` for capability specs and change proposals
- GitHub Actions for CI

## Project Conventions

### Code Style
- Follow Julia community conventions.
- Keep source files thin and focused; delegating heavy lifting to `Coverage.jl`,
  `SnoopCompile.jl`, `JET.jl`, and `ReTestItems.jl`.
- Target ~2000 LOC total for the package (`src/`).

### Architecture Patterns
- Per-item subprocess isolation is a hard constraint: coverage counters and
  inference state cannot be shared across test items.
- Dual-indexing (`line_to_tests` + `test_to_lines`) trades disk for query speed
  — do not collapse to a single direction.
- Analysis layers are additive: inference and static edges never *remove*
  selections, only add them.

### Testing Strategy
- Follow TDD: write the failing test first, then make it pass, then tidy.
- `just test` must pass at each phase before advancing.
- Coverage layer is the primary correctness gate.

### Git Workflow
- Track work in beads issues; use `wai` for reasoning and handoffs.
- Keep changes small and push once local checks pass.
- Tag releases following Julia package conventions (v0.x.y).

## Important Constraints

- Per-item subprocess recording is the preferred approach for Julia coverage
  and inference attribution. A spike confirmed that no in-process coverage
  reset API is available (see `.wai/research/2026-07-15-reset-coverage-spike.md`).
  Inference state cannot
  be reset in-process regardless, making subprocess isolation the safe
  default for both layers.
- The index is never checked into the repo; it lives in CI artifact storage.
- The runner environment (`scripts/TestimonialRunner/`) must be a separate
  workspace member to avoid dependency conflicts with `JuliaInterpreter.jl`.
- `schema_version` in `CoverageIndex` must be bumped on any breaking struct
  change to enable cache invalidation.
- **Adapter mode** is read-only with respect to the local `CoverageIndex`.
  All coverage data writes go to testaruda's SQLite store via the `ingest`
  response. The standalone index and testaruda's store are independent and
  can diverge — the user must understand which mode they are in.

## External Dependencies

- GitHub for source hosting and CI artifact storage
- `wai`, `bd`, and `openspec` CLIs in contributor environments
- Julia 1.12+ (required for `[workspace]` monorepo support; `[sources]` is supported since 1.11)
- [testaruda](https://github.com/charly-vibes/testaruda) (optional — only needed for adapter mode)

## References

- [ReTestItems.jl](https://github.com/JuliaTesting/ReTestItems.jl)
- [Coverage.jl](https://github.com/JuliaCI/Coverage.jl)
- [SnoopCompile.jl](https://github.com/timholy/SnoopCompile.jl)
- [JET.jl](https://github.com/aviatesk/JET.jl)
- [testaruda](https://github.com/charly-vibes/testaruda) — language-agnostic test impact analysis orchestrator; Testimonial.jl's adapter mode speaks its protocol
