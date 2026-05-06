## ADDED Requirements

### Requirement: @testitem discovery
The system SHALL discover all `@testitem` blocks in a monorepo by scanning
source files matching the configured `test_directories` glob patterns.

For each discovered item the system SHALL produce a `TestItemRef` with the
absolute file path, item name, declared tags, and file content hash.

#### Scenario: Basic discovery
- **WHEN** `record_all` is invoked in a monorepo with `@testitem` blocks
- **THEN** every `@testitem` in files under `test_directories` is discovered
- **AND** each is represented as a `TestItemRef`

#### Scenario: Item name extraction
- **WHEN** a file contains `@testitem "Black-Scholes call pricing" tags=[:fast]`
- **THEN** the discovered `TestItemRef` has `item_name = "Black-Scholes call pricing"`
  and `tags = [:fast]`

#### Scenario: Empty test directory
- **WHEN** no `@testitem` blocks are found
- **THEN** `record_all` completes without error and the index has zero entries

### Requirement: Per-item subprocess recording
The system SHALL record each `@testitem` in an isolated subprocess using
`julia --code-coverage=user` so that coverage counters are attributed to
exactly that item and are not contaminated by other items.

Each subprocess MUST run `ReTestItems.runtests` filtered to a single item
by name, against a dedicated runner environment
(`scripts/TestimonialRunner/Project.toml`).

#### Scenario: Subprocess invocation
- **WHEN** `record_item(test_file, item_name)` is called
- **THEN** a subprocess is launched with `--code-coverage=user` and
  `--project=scripts/TestimonialRunner`
- **AND** only the named item is executed in that subprocess

#### Scenario: Coverage sidecar parsing
- **WHEN** the subprocess exits successfully
- **THEN** `.jl.cov` sidecar files produced by the subprocess are parsed via
  `Coverage.process_file`
- **AND** only lines with `count > 0` are recorded as hit lines
- **AND** the sidecar files are removed after parsing

#### Scenario: Subprocess failure
- **WHEN** the subprocess exits with a non-zero status code
- **THEN** the failure is logged with the item name and file
- **AND** recording continues for remaining items
- **AND** the failed item is not included in the index

#### Scenario: Subprocess timeout
- **WHEN** a subprocess exceeds `timeout_per_item_seconds` (default 300 s)
- **THEN** it is killed and treated as a failure
- **AND** the failure is logged with the item name, file, and timeout duration

### Requirement: Per-item cache
The system SHALL skip re-recording a test item when a cached record exists
for its cache key (`file_hash + "_" + item_name`) in `.testimonial/items/`.

#### Scenario: Cache hit
- **WHEN** `record_all` is invoked and a valid cache record exists for an item
- **THEN** the subprocess is not spawned for that item
- **AND** the cached `ItemCoverage` is used directly in index construction

#### Scenario: Cache miss on file change
- **WHEN** a test file's content changes between recording runs
- **THEN** all items in that file have new cache keys (new `file_hash`)
- **AND** those items are re-recorded

### Requirement: Parallel recording
The system SHALL record multiple test items concurrently using
`Threads.@threads` with `nthreads = CPU_THREADS ÷ 2` to leave headroom
for the spawned subprocesses.

#### Scenario: Parallel execution
- **WHEN** `record_all` is run with multiple uncached items
- **THEN** multiple subprocesses run concurrently, up to the configured
  thread count
- **AND** the total wall-clock time is less than sequential time for the
  same item set

### Requirement: Index construction from per-item records
The system SHALL construct a `CoverageIndex` by loading all per-item records
from `.testimonial/items/` and building the dual-direction index.

#### Scenario: Index construction
- **WHEN** all per-item records are loaded
- **THEN** `line_to_tests` contains every (file, line) pair covered by at
  least one item, with the correct `TestItemRef` list
- **AND** `test_to_lines` contains every item's full coverage footprint

#### Scenario: Incremental index update
- **WHEN** only some items are re-recorded (cache hits for the rest)
- **THEN** the new index combines fresh records for changed items with cached
  records for unchanged items
- **AND** the resulting index is equivalent to a full re-recording

### Requirement: record_all public API
The system SHALL expose `Testimonial.record_all(; incremental=true, force=false)`
as the primary entry point for building or updating the coverage index.

- With `incremental=true` (default): only re-records items whose test files
  have changed since the last index build.
- With `force=true`: re-records all items regardless of cache state.

#### Scenario: Full recording
- **WHEN** `record_all(incremental=false)` is called
- **THEN** all discovered items are re-recorded and a fresh index is built

#### Scenario: Incremental recording
- **WHEN** `record_all(incremental=true)` is called and some test files
  are unchanged
- **THEN** only items in changed test files are re-recorded
- **AND** items in unchanged files use cached records

### Requirement: record_item public API
The system SHALL expose `Testimonial.record_item(test_file, item_name)`
for single-item recording, primarily for debugging and interactive use.

#### Scenario: Single item record
- **WHEN** `record_item("/abs/path/test.jl", "My test")` is called
- **THEN** exactly one subprocess is spawned for that item
- **AND** the result is an `ItemCoverage` struct with the item's coverage data
