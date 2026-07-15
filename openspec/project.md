# Project Context

## Purpose

Testimonial.jl is a test impact analysis tool for Julia monorepos. Given a set
of code changes (from a git diff), it selects the minimal set of `@testitem`s
that must run to validate those changes — turning a 30-minute CI test suite
into a 30-second feedback loop on most PRs.

It operates in two phases:
1. **Recording** (nightly on main): runs each `@testitem` in an isolated
   subprocess, captures coverage and inference data, and builds a
   `CoverageIndex`.
2. **Smart selection** (every PR): parses the git diff, queries the index, and
   invokes `ReTestItems.runtests` on the selected items only.

The primary intended deployment context is Julia monorepos with 10+ packages
and hundreds of `@testitem`s (e.g., SundaeVolatility scale).

## Domain Model

The core abstraction is the **`CoverageIndex`** — a dual-indexed artifact that
maps source lines → test items (for fast impact queries) and test items →
source lines (for incremental re-recording). Recording runs each `@testitem`
in a **separate subprocess**. While Julia 1.11 introduced the ability to reset
coverage counters (`Base.reset_coverage()`), isolation is still required because
inference fires only on the first invocation, and separate processes ensure a
pristine global state for each test.

Three analysis layers stack for complete coverage:

| Layer | Mechanism | Primary Use |
|---|---|---|
| **Coverage** | `--code-coverage=user` | Precise line attribution (~95% of PRs) |
| **Inference** | `SnoopCompile.@snoopi_deep` | Newly added methods not yet in coverage |
| **Static** | `JET.report_package` | Abstract dispatch paths, declared entrypoints |

## Capability Specs

| Capability | Purpose |
|---|---|
| `coverage-index` | `CoverageIndex` data model, persistence (`.testimonial/index.jls`) |
| `recording` | Per-item subprocess recording protocol, parallelism, index construction |
| `smart-selection` | Git diff → query pipeline, coverage gap detection, `smart_run` orchestration |
| `inference-layer` | `@snoopi_deep` capture and inference edge construction |
| `static-layer` | JET-based entrypoint analysis and static edge construction |
| `cli` | Command-line interface (`testimonial record`, `run`, `explain`, `gaps`, `info`) |
| `configuration` | `Testimonial.toml` parsing, entrypoints, tag overrides, selection caps |
| `ci-integration` | Two-workflow pattern (recording + PR), index artifact handling |
| `safety-invariants` | Soundness invariant, always-run set, scoped fallback, incident recording, must-run rules, flaky detection, shadow mode, reconciliation, promotion protocol |
| `runtime-feedback` | Post-run ingestion, runtime edge creation, run history, idempotent ingest, external input recording |
| `confidence-scoring` | Per-test confidence computation, per-component minimum confidence, threshold-based fallback gating |
| `component-architecture` | Per-component indices, component graph, bottom-up resolution, cached selection, parallel selection, shard plans |
| `provenance` | Reason chains, exclusion reasoning, persisted provenance, layered provenance view |

## Implementation Phases

Per the specification:
- **Phase 1 (MVP):** coverage layer only — `record_all`, `query`, `smart_run`
- **Phase 2:** inference layer — `@snoopi_deep` capture and inference edges
- **Phase 3:** static layer — JET entrypoint analysis, `Testimonial.toml` config
- **Phase 4:** CI integration, CLI polish, GitHub PR comments

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
  and inference attribution. Although coverage can be reset in 1.11+, inference state cannot, making subprocess isolation mandatory for Phase 2.
- The index is never checked into the repo; it lives in CI artifact storage.
- The runner environment (`scripts/TestimonialRunner/`) must be a separate
  workspace member to avoid dependency conflicts with `JuliaInterpreter.jl`.
- `schema_version` in `CoverageIndex` must be bumped on any breaking struct
  change to enable cache invalidation.

## External Dependencies

- GitHub for source hosting and CI artifact storage
- `wai`, `bd`, and `openspec` CLIs in contributor environments
- Julia 1.12+ (required for `[workspace]` monorepo support; `[sources]` is supported since 1.11)

## References

- [ReTestItems.jl](https://github.com/JuliaTesting/ReTestItems.jl)
- [Coverage.jl](https://github.com/JuliaCI/Coverage.jl)
- [SnoopCompile.jl](https://github.com/timholy/SnoopCompile.jl)
- [JET.jl](https://github.com/aviatesk/JET.jl)
- [testaruda](https://github.com/sashakile/testaruda.jl) — proxy-based test impact analysis tool; prior art for reason-chain design, confidence heuristics, and incident promotion protocol
