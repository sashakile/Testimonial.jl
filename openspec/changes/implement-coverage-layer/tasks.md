## 0. Technical Spikes

- [ ] 0.1 Benchmark subprocess overhead: Measure recording time for 1000+ items
      on standard CI hardware to validate performance assumptions
- [ ] 0.2 Validate coverage sidecar attribution: Confirm `Coverage.process_file`
      correctly maps hits in a symlinked shadow tree back to source files

## 1. Project Scaffold

- [ ] 1.1 Create `Project.toml` with package metadata and dependencies
      (`Coverage`, `ReTestItems`, `Dates`, `SHA`, `Serialization`)
- [ ] 1.2 Create `src/Testimonial.jl` with module skeleton and re-exports
- [ ] 1.3 Create `test/runtests.jl` and verify `just test` runs (empty suite passes)
- [ ] 1.4 Create `scripts/TestimonialRunner/Project.toml` — the isolated runner
      environment with `Testimonial`, `ReTestItems`, `Coverage` as deps

## 2. Data Model & Persistence (`src/Types.jl`, `src/Persistence.jl`)

- [ ] 2.1 Define enums and structs in `src/Types.jl`:
      `TestItemRef`, `ImpactReasonKind`, `ImpactReason`, `ImpactResult`,
      `CoverageGap`, `ItemCoverage`, and `CoverageIndex`
- [ ] 2.2 Implement `==` / `hash` for `TestItemRef` (exclude `file_hash` and `tags`)
- [ ] 2.3 Implement `save_index`, `load_index`, `save_item_record`, `load_item_record`
      in `src/Persistence.jl` using `Serialization`
- [ ] 2.4 Implement atomic write (write to `.tmp` then `mv`) in `Persistence.jl`
- [ ] 2.5 Implement schema and Julia version checks on load
- [ ] 2.6 Write unit tests for struct equality, hash, round-trip persistence,
      schema mismatch rejection

## 3. AST Parser (`src/ASTParser.jl`)

- [ ] 3.1 Implement `discover_testitems(dirs::Vector{String}) -> Vector{TestItemRef}`
      using regex / AST walk to find `@testitem "name"` blocks
- [ ] 3.2 Extract `tags=[...]` declarations from each `@testitem`
- [ ] 3.3 Compute `file_hash` (SHA-256 hex prefix) for each test file
- [ ] 3.4 Write unit tests with synthetic test files containing various
      `@testitem` forms (with and without tags, multiple per file)

## 4. Git Diff Parser (`src/GitDiff.jl`)

- [ ] 4.1 Implement `parse_unified_diff(diff_text::String, repo_root::String)`
      returning `Dict{String, Set{Int}}`
- [ ] 4.2 Handle new files, deleted files, and renamed files correctly
- [ ] 4.3 Resolve relative diff paths to absolute form
- [ ] 4.4 Write unit tests against sample diff strings for each case

## 5. Coverage Layer (`src/CoverageLayer.jl`)

- [ ] 5.1 Define `abstract type AbstractRunner end` and `struct SubprocessRunner <: AbstractRunner`
- [ ] 5.2 Implement `record_item(runner::AbstractRunner, ref::TestItemRef, ...)`
- [ ] 5.3 Implement `record_item_subprocess` (logic in `SubprocessRunner`)
      — spawns subprocess in a unique `tempdir` with a symlinked shadow tree, returns `ItemCoverage` or `nothing` on failure
- [ ] 5.4 Implement subprocess command construction
      (`julia --code-coverage=user --project=<runner> driver.jl`) with `TESTIMONIAL_ITEM` and `TESTIMONIAL_FILE` env vars
- [ ] 5.5 Implement `driver.jl` in `scripts/TestimonialRunner/` — reads
      env vars, calls `ReTestItems.runtests` with file and name filters
- [ ] 5.6 Implement `.jl.cov` sidecar parsing via `Coverage.process_file`
- [ ] 5.7 Implement timeout handling (kill subprocess if exceeded)
- [ ] 5.8 Implement per-item cache read/write (`.testimonial/items/<key>.jls`)
- [ ] 5.9 Write integration test: record a simple `@testitem` in a scratch
      package and verify the correct lines appear in `ItemCoverage`
- [ ] 5.10 Write unit test for `record_item` using a `MockRunner` to verify
      command construction without spawning processes

## 6. Index Builder (`src/IndexBuilder.jl`)

- [ ] 6.1 Implement `build_index(items_dir::String) -> CoverageIndex`
      from per-item records in `src/IndexBuilder.jl`
- [ ] 6.2 Implement `record_all(items, runner=SubprocessRunner(); incremental=true, force=false)` —
      record all items, build CoverageIndex, persist. The `runner` kwarg allows
      injecting a mock for testing. Parallel recording via `Threads.@threads`.
- [ ] 6.3 Implement `record_item(test_file, item_name)` for single-item
      debugging
- [ ] 6.4 Implement cache cleanup (orphaned record deletion) in `IndexBuilder.jl`
- [ ] 6.5 Write integration test: record two items in a scratch monorepo
      and verify the resulting `CoverageIndex` is correct

## 7. Query Engine (`src/Query.jl`)

- [ ] 7.1 Implement `query(providers::Vector{ImpactProvider}, index, changed) -> Vector{ImpactResult}`
      with deduplication and reason accumulation. Implement `CoverageProvider <: ImpactProvider`.
- [ ] 7.2 Implement test-file-changed detection (changed file under
      `test_directories` → select all items in file)
- [ ] 7.3 Implement `query_files(index, files) -> Vector{ImpactResult}`
- [ ] 7.4 Implement `coverage_gaps(index, changed) -> Vector{CoverageGap}`
      with `nearest_covered_lines` population
- [ ] 7.5 Write unit tests with a synthetic `CoverageIndex` covering:
      single hit, multi-line hit, gap detection, test-file-changed
- [ ] 7.6 Implement `is_index_stale(index) -> Bool` — checks whether
      `built_at` is older than a threshold (default: 24h) or `julia_version`
      mismatches. Used by the standalone CLI for fallback decisions.

## 8. Standalone CLI (`src/CLI.jl`) — replaces old Orchestrator + Inspector

- [ ] 8.1 Implement `testimonial record` — calls `ASTParser.discover_testitems`,
      `IndexBuilder.record_all`, persists CoverageIndex
- [ ] 8.2 Implement `testimonial run <ref-range>` — loads index, checks staleness,
      parses git diff, queries, runs selected tests. Falls back to full suite
      if index is missing or stale.
- [ ] 8.3 Implement `testimonial explain <test_file> <item_name>` — looks up
      item in CoverageIndex, returns list of covered files/lines
- [ ] 8.4 Implement `testimonial gaps <ref-range>` — reports changed lines
      with no recorded coverage
- [ ] 8.5 Implement cold start handling: if no index exists, emit informative
      message and run full suite
- [ ] 8.6 Write integration tests: `testimonial record` followed by
      `testimonial run` on a known change selects the correct items
- [ ] 8.7 Implement a **seeded-fault recall check** utility: given a source file,
      inject a known semantic mutation, verify the test that should catch it is
      still selected. This is a pre-deployment gate, not a unit test — it validates
      the end-to-end pipeline.

## 9. Protocol Adapter (`src/Protocol.jl`)

- [ ] 9.1 Implement `handle(line::String) -> String` — dispatch one JSON command
      to the appropriate handler function
- [ ] 9.2 Implement `run_adapter_protocol()` — main loop reading stdin,
      dispatching, writing stdout
- [ ] 9.3 Implement `handle_handshake` — static response with capabilities
      (`runtime_edges: true`, `granularity: "file"`, `symbol_model_complete: false`)
- [ ] 9.4 Implement `handle_discover` — calls `ASTParser.discover_testitems`,
      returns JSON node list
- [ ] 9.5 Implement `handle_ingest` — calls `CoverageLayer.record_item` for
      each item in the request, constructs edge data from `ItemCoverage`,
      returns edges inline. **No local index persistence** — edges go to
      testaruda's SQLite store via the response.
- [ ] 9.6 Implement `handle_static_deps` — if no coverage recorded yet, return
      `unresolved` for all changed files. Otherwise, query the in-memory
      coverage map built by `ingest` calls in this session.
- [ ] 9.7 Implement `handle_fingerprint` — SHA-256 hash of file contents
      (standardized instead of BLAKE3 to avoid a non-stdlib dependency)
- [ ] 9.8 Implement `handle_run_args` — emit `ReTestItems.runtests` invocation
      args filtered by `(test_file, item_name)` pairs
- [ ] 9.9 Create `bin/testaruda_adapter.jl` — thin shell script calling
      `Testimonial.run_adapter_protocol()`
- [ ] 9.10 Write unit tests: send JSON commands via stdin, verify correct
      JSON responses on stdout. Include error cases (malformed JSON, unknown
      command, recording failure). Validate error response format:
      `{ "error": { "message": "..." } }`.

## 10. Public API Surface (`src/Testimonial.jl`)

- [ ] 10.1 Include all sub-modules in `src/Testimonial.jl`
- [ ] 10.2 Re-export all public functions:
      `record_all`, `record_item`, `query`, `query_files`,
      `run`, `explain`, `coverage_gaps`, `run_adapter_protocol`
- [ ] 10.3 Re-export public types:
      `CoverageIndex`, `TestItemRef`, `ImpactResult`, `ImpactReason`,
      `ImpactReasonKind`, `CoverageGap`
- [x] 10.4 Verify `just test` passes the full unit + integration test suite *(merged into 10.1)*
- [x] 10.5 Verify `openspec validate implement-coverage-layer --strict` passes *(merged into 10.1)*