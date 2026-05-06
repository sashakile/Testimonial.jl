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

- [ ] 5.1 Implement `record_item_subprocess(ref::TestItemRef, runner_project::String)`
      — spawns subprocess in a unique `tempdir` to avoid `.cov` contention, returns `ItemCoverage` or `nothing` on failure
- [ ] 5.2 Implement subprocess command construction
      (`julia --code-coverage=user --project=<runner> driver.jl`) with `TESTIMONIAL_ITEM` and `TESTIMONIAL_FILE` env vars
- [ ] 5.3 Implement `driver.jl` in `scripts/TestimonialRunner/` — reads
      env vars, calls `ReTestItems.runtests` with file and name filters
- [ ] 5.4 Implement `.jl.cov` sidecar parsing via `Coverage.process_file`
- [ ] 5.5 Implement timeout handling (kill subprocess if exceeded)
- [ ] 5.6 Implement per-item cache read/write (`.testimonial/items/<key>.jls`)
- [ ] 5.7 Write integration test: record a simple `@testitem` in a scratch
      package and verify the correct lines appear in `ItemCoverage`

## 6. Index Builder (`src/IndexBuilder.jl`)

- [ ] 6.1 Implement `build_index(items_dir::String) -> CoverageIndex`
      from per-item records in `src/IndexBuilder.jl`
- [ ] 6.2 Implement `record_all(; incremental=true, force=false)` with
      parallel recording via `Threads.@threads`
- [ ] 6.3 Implement `record_item(test_file, item_name)` for single-item
      debugging
- [ ] 6.4 Implement cache cleanup (orphaned record deletion) in `IndexBuilder.jl`
- [ ] 6.5 Write integration test: record two items in a scratch monorepo
      and verify the resulting `CoverageIndex` is correct

## 7. Query Engine (`src/Query.jl`)

- [ ] 7.1 Implement `query(index, changed) -> Vector{ImpactResult}`
      with deduplication and reason accumulation
- [ ] 7.2 Implement test-file-changed detection (changed file under
      `test_directories` → select all items in file)
- [ ] 7.3 Implement `query_files(index, files) -> Vector{ImpactResult}`
- [ ] 7.4 Implement `coverage_gaps(index, changed) -> Vector{CoverageGap}`
      with `nearest_covered_lines` population
- [ ] 7.5 Write unit tests with a synthetic `CoverageIndex` covering:
      single hit, multi-line hit, gap detection, test-file-changed

## 8. Smart Runner (`src/Orchestrator.jl`)

- [ ] 8.1 Implement `smart_run(; base_ref, strict_coverage, dry_run)` in `src/Orchestrator.jl`
- [ ] 8.2 Integrate index load, git diff parse, query, gap handling (include Project/Manifest change detection)
- [ ] 8.3 Implement `on_coverage_gap` policy dispatch
      (`fallback_fast`, `fail`, `warn`)
- [ ] 8.4 Implement stale index warning (> 24 h)
- [ ] 8.5 Implement `max_selected_items` cap with fallback to full suite
- [ ] 8.6 Implement dry-run output (selected items + reasons, no test execution)
- [ ] 8.7 Write unit tests for each coverage-gap policy branch

## 9. Inspection APIs (`src/Inspector.jl`)

- [ ] 9.1 Implement `explain(test_file, item_name) -> Vector{String}` in `src/Inspector.jl`
- [ ] 9.2 Implement `index_info() -> NamedTuple` in `src/Inspector.jl`
- [ ] 9.3 Write tests for both functions

## 10. Public API Surface (`src/Testimonial.jl`)

- [ ] 10.1 Include all sub-modules in `src/Testimonial.jl`
- [ ] 10.2 Re-export all public functions:
      `record_all`, `record_item`, `query`, `query_files`,
      `smart_run`, `explain`, `coverage_gaps`, `index_info`
- [ ] 10.3 Re-export public types:
      `CoverageIndex`, `TestItemRef`, `ImpactResult`, `ImpactReason`,
      `ImpactReasonKind`, `CoverageGap`
- [ ] 10.4 Verify `just test` passes the full unit + integration test suite
- [ ] 10.5 Verify `openspec validate implement-coverage-layer --strict` passes
