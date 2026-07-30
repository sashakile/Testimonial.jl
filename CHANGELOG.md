---
title: Changelog
description: Release history and version changelog for Testimonial.jl
category: reference
---

# Changelog

**TL;DR:** All notable changes to Testimonial.jl, organized by version. New features, bug fixes, and infrastructure updates.

All notable changes to Testimonial.jl are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — 2026-07-30 — Highlights

**For users:**
- 🔬 **Inference Layer (Phase 2)** — `@snoopi_deep` capture, `InferenceProvider` in query pipeline, inference edges in adapter ingest
- 🏗️ **Static Layer (Phase 3)** — JET-based entrypoint analysis, `StaticProvider`, `StaticLayerKind`
- 🔌 **Protocol adapter enhancements** — `static-deps` handler returns DepEdge array format, `inference_edges` in ingest response
- 📖 **Documentation overhaul** — Diátaxis restructure, tutorial, how-to, error reference, AI-readiness (llms.txt)

**For developers:**
- All 3 analysis layers (coverage, inference, static) now complete and active
- 1250+ quick tests across all layers
- 3-layer integration tests for multi-provider query pipeline

---

## Detailed Changes

## [0.3.0] — 2026-07-30

### Added

#### Inference Layer (Phase 2)
- `inference_edges` field on `CoverageIndex` (caller→callee 6-tuples per `TestItemRef`)
- `parse_inference_trace()` — deserializes driver.jl `inference_trace.jls` sidecar
- `inference_content_units()` — projects caller source locations as deduped content units
- `merge_inference_edges()` — additive, deduped merge preserving all other index fields
- `InferenceProvider` — query provider selecting tests when inference edge caller files change
- `INFERRED` LayerKind in provenance links
- `InferenceEdge` type exported from `Testimonial`
- Inference trace capture in driver.jl (SnoopCompile `@snoopi_deep` wrapper)
- Inference trace sidecar cleaned up after consumption (not in `_collect_coverage`)
- `inference_edges` in adapter ingest response (DepEdge array format, `origin: "inference"`)
- 3 integration tests for multi-provider (runtime + inference) query pipeline

#### Static Layer (Phase 3)
- `static_edges` field on `CoverageIndex` (file → `Set{TestItemRef}`)
- `layer_data` field on `CoverageIndex` for extensible metadata
- `StaticLayer` module with `run_static_analysis()` — JET-based entrypoint analysis with graceful fallback to function-name scanning
- `StaticProvider` — query provider for static analysis edges
- `StaticLayerKind` in explain output and provenance links
- Static-deps handler returns structured DepEdge array format
- Enhanced `static-deps` handler: concrete edges from `session_static_edges` when available, empty array fallback
- `_ensure_session_static_edges_loaded()` — loads static edges from `CoverageIndex` on disk
- `_emit_static_edges()` — emits DepEdge entries from static analysis data
- 7 static layer integration tests

#### Protocol Adapter
- `static-deps` handler returns DepEdge array `[{from, to, weight, origin}]` instead of `{file → "unresolved"}` dict
- `inference_edges` field in ingest response alongside `runtime_edges`
- `_build_inference_edges()` — reads inference trace, parses, builds DepEdge entries
- `_cleanup_inference_trace()` in IndexBuilder for stale trace cleanup
- Batch coverage recording by file in `_handle_ingest_run_output`

#### Documentation
- Full Diátaxis restructure (tutorial, how-to, explanation, reference)
- Getting Started tutorial (`docs/src/tutorial.md`)
- How-to guide for component boundaries (`docs/src/howto-components.md`)
- Error Reference with troubleshooting tables (`docs/src/errors.md`)
- Expanded Architecture: data flow diagrams, pipelines, CI artifact flow
- AI-readiness: `llms.txt`, YAML front matter on all pages, TL;DR summaries
- Documenter.jl Pages deployment (no `gh-pages` branch)
- Custom CSS for fixed header offset and top-bar nav tree fix

### Changed
- `static-deps` handler response format: array of DepEdge dicts instead of filename→status dict
- `_collect_coverage` no longer cleans up inference trace — caller is responsible
- `openspec/project.md` capability statuses updated (inference/static: Planned → Active)
- Architecture doc updated: StaticLayer no longer "planned"

### Fixed
- `StringIndexError` in `dont list` from multi-byte UTF-8 (char-safe truncation)
- `discover` handler default dir: use `pwd()` instead of `@__DIR__` for external adapter mode
- SnoopCompile optional: supports Julia < 1.12 without inference (graceful fallback)
- SnoopCompile v2/v3 dual dispatch via runtime eval
- JET weakdep to avoid transitive dep conflict in Runner project
- Batch coverage recording: file-grouped subprocess per file (not per-item)
- Docs build: cross-build-directory link rejection fix
- Docs deploy: use Pages API (no `gh-pages` branch)
- Docs top bar: custom CSS for fixed header offset, nested nav tree fix

## [0.2.0] — 2026-07-29

### Added

#### Coverage Layer — Core Engine
- `TestItemRef`, `CoverageIndex`, `ImpactResult`, `ImpactReason`, `CoverageGap`,
  `ItemCoverage` types with dual-indexed (`line_to_tests` + `test_to_lines`) data model
- Per-item subprocess recording via `SubprocessRunner` with `driver.jl` in isolated workspace
- `.jl.cov` sidecar parsing via `Coverage.process_file`
- LCOV tracefile parser for Julia 1.12+ coverage format
- `build_index`, `record_all`, `record_item` with parallel recording (`Threads.@threads`)
- Per-item cache (`.testimonial/items/<key>.jls`) with `file_hash`-based invalidation
- Cache cleanup for orphaned records
- `discover_testitems` AST parser with `@testitem` name, tags, and `file_hash` extraction
- `parse_unified_diff` for git diff parsing (new, deleted, renamed files)
- `query`, `query_files`, `coverage_gaps` with `nearest_covered_lines` and `is_index_stale`
- Test-file-changed detection (changed file under `test_directories` → select all items)
- Provider-based extensible query pipeline (`CoverageProvider`, `ImpactProvider` trait)
- `MockRunner` for unit testing without subprocess spawning
- Atomic write (`.tmp` → `mv`) for persistence
- `schema_version` + `julia_version` checks on index load
- Cold start handling (no index → run full suite with informative message)
- Staleness detection (24h threshold + Julia version mismatch → full suite fallback)
- Conservative fallback: run everything on staleness, missing index, or coverage gaps

#### CLI — Standalone Mode
- `testimonial record` — discover items, record coverage, build and persist index
- `testimonial run` — load index, check staleness, parse diff, query, run selected tests
- `testimonial explain` — look up item in index, show covered files/lines
- `testimonial gaps` — report changed lines with no recorded coverage
- `testimonial incidents` — list, dismiss, and promote missed-selection incidents
- `--shadow` / `--enforcing` flags for safety mode override
- `--base-ref` flag for custom base git ref
- `--shards N` flag for balanced shard output

#### Protocol Adapter — testaruda Integration
- `run_adapter_protocol()` — JSON stdin/stdout main loop
- `handle_handshake` — capabilities response (`runtime_edges: true`, `granularity: "file"`)
- `handle_discover` — returns JSON node list from `ASTParser`
- `handle_ingest` — records coverage per item, returns edges inline
- `handle_static_deps` — unresolved fallback or in-memory query
- `handle_fingerprint` — SHA-256 file hash
- `handle_run_args` — `ReTestItems.runtests` invocation args
- Per-session in-memory coverage map for `static-deps` across `ingest` calls

#### Runtime Feedback
- `RunHistoryEntry` struct with outcome, duration, attempt_count, failure_rate
- `RunHistory` persistence at `.testimonial/run_history.jls` with atomic rename
- `ingest()` function — post-run coverage sidecar parsing and index merge
- `auto_ingest` flag on `run()` — automatic ingestion after test execution
- `runtime_edges` field on `CoverageIndex` — post-run learning
- `runtime_edge_provider` — query provider for runtime edges
- Idempotent ingestion with `.testimonial/ingested_runs.jls` and run key pruning
- `external_inputs` field on `TestItemRef` with `@testitem "name" external_inputs=[...]` syntax
- File-grouped subprocess batching (`record_batch`, `TESTIMONIAL_ITEMS` env var)

#### Confidence Scoring
- `compute_confidence()` — geometric mean of 4 signals: freshness, recording quality,
  layer coverage, history quality
- `ConfidenceConfig` with `threshold`, `stale_threshold_hours`, per-component overrides
- `group_items_by_component` and `components_below_threshold` for fallback gating
- Per-test confidence in dry-run output, `explain` output, and `smart_run` summary
- `confidence_threshold` and `stale_threshold_hours` config keys in `Testimonial.toml`

#### Provenance & Explainability
- `ProvenanceLink` struct with layer, content_unit, detail, next
- `LayerKind` enum (`Coverage`, `Inference`, `Static`, `Manual`, `MustRun`)
- Reason chains built during query — trace from changed line to test
- Exclusion reasoning: `explain(exclude=true)` with actionable suggestions
- `format_reason` / `format_impact_result` display formatters
- Persisted provenance at `.testimonial/provenance/<run_key>.jls`
- Sliding-window pruning (keep last N runs, configurable)
- `--layers` flag for `explain` with LayerKind grouping and intersection/union semantics

#### Safety Invariants
- `AlwaysRunReason` enum: `LAST_RUN_FAILED`, `NEWLY_ADDED`, `NO_HISTORY`, `MUST_RUN`, `QUARANTINED`
- `always_run_reason` field on `TestItemRef` with eviction after N consecutive passes
- `MustRunRule` config struct with glob pattern → test tag matching
- `must_run` section in `Testimonial.toml` schema
- `must_run_with_fallback_priority` — scoped fallback wins, must-run logged
- `FallbackReason` field on `ImpactResult` for unresolved files
- `scoped_fallback` with pre-boundary degradation (global fallback before component graph)
- Environment fingerprint (`julia_version` + `Project.toml` hash) in `CoverageIndex`
- Flaky detector — inconsistent outcomes across retries → flaky label
- Quarantine metadata — test is selected and run, outcome excluded from pass/fail
- Flaky test edge exclusion from runtime feedback
- `MissedSelectionIncident` struct with `Candidate`/`Promoted`/`Dismissed` status
- Incident persistence at `.testimonial/incidents.jls` (survives index rebuilds)
- Candidate → promoted promotion after 3 same-failure occurrences
- Manual edge creation on promotion
- Shadow mode: compute selection, log it, run all tests, compare outcomes
- `reconcile()` — full-run pipeline with counterfactual selection comparison
- Reconciliation reports at `.testimonial/reconciliation/`
- `[safety] mode` config key (`"shadow"` / `"enforcing"`, default: `"shadow"`)
- Promotion readiness indicator in `index_info`
- `scripts/seeded_fault_test.jl` — 5 seed patterns, exit non-zero on missed selection

#### Component Boundary
- `component::String` field on `TestItemRef` (included in equality and hash)
- `inter_component_edges::Dict{String, Set{String}}` on `CoverageIndex`
- `discover_components()` from workspace `Project.toml`
- Component auto-detection with test-file-to-component mapping
- `components` override in `Testimonial.toml` for non-workspace projects
- `.testimonial/` restructuring: routing file + per-component subdirs
- `migrate_index()` — flat-to-per-component migration with schema version bump
- Per-component `record_all`, `load_index`, `build_index`
- Component graph construction and persistence
- Bottom-up component resolution before per-component selection
- Parallel per-component query via `Threads.@threads`
- Dependency fingerprint per component with cached selection
- Cache invalidation on fingerprint change
- `balance_shards()` — greedy duration-balancing shard assignment
- `--shards N` option on `run()`

### Changed
- Architecture updated from monolithic to two-layer (Julia core + protocol adapter)
- Modular architecture with 9 focused modules to prevent God Modules
- `CoverageIndex` now uses `Dict{Symbol, Any}` `layer_data` for extensibility
- `SCHEMA_VERSION` bumped for per-component data model

### Fixed
- `StringIndexError` in `_parse_external_inputs` from multi-byte UTF-8 characters
- Thread-safe `MockRunner` for parallel `record_all`
- `discover` handler defaults to `test/` path when no params provided
- Module import ordering — types before includes
- Protocol path resolution for adapter mode
- `.jl.cov` sidecar parsing in symlinked shadow trees
- Missing newline between `include()` calls in `test/runtests.jl`
- `Coverage.process_file` attribution in shadow trees
- CI workflow: tool installation from crates.io and npm
- CI workflow: `--locked` removed from build steps (Rust version mismatch)
- `espectacular` CI: commit `.espectacular` config

### Documentation
- Added CLI reference, API reference, and architecture docs
- Documented safety invariants, promotion protocol, and component boundary
- Documented confidence scoring and provenance features
- Documented environment fingerprint and always-run set
- Added `docs/` directory with Documenter.jl setup for GitHub Pages
- All openspec change proposals archived (7 total)

### Infrastructure
- GitHub Actions CI workflow (Julia 1.11 + 1.12, pretender, espectacular, openspec)
- Nightly recording workflow (06:00 UTC, full coverage on main, artifact upload)
- Scheduled reconciliation workflow
- GitHub Actions docs workflow (new Pages API, no `gh-pages` branch)
- Lefthook pre-commit hooks (pretender, openspec, Julia syntax, no debug prints)
- Lefthook pre-push hooks (Julia tests, pretender, beads integrity)
- `dont` claim gate wiring (53 claims, lefthook pre-push)
- `pretender` code quality check configuration
- `espectacular` spec-level validation configuration