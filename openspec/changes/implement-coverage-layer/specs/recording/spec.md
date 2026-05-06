## ADDED Requirements

### Requirement: [REC-001] @testitem discovery
The system SHALL discover all `@testitem` blocks in a monorepo by scanning
source files matching the `test_directories` glob patterns (Phase 1 hardcoded
default: `["**/test"]`; configurable in Phase 3).

For each discovered item the system SHALL produce a `TestItemRef` with the
absolute file path, item name, declared tags, and file content hash. To avoid
identity collisions, `@testitem` names MUST be unique within a single test file.

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

### Requirement: [REC-002] Per-item subprocess recording
The system SHALL record each `@testitem` in an isolated subprocess using
`julia --code-coverage=user` so that coverage counters are attributed to
exactly that item and are not contaminated by other items.

To prevent `.jl.cov` file contention during parallel recording, each
subprocess SHALL run within a unique temporary directory. The system SHALL
ensure the subprocess can resolve source file paths (e.g., by setting the
current working directory to the project root and configuring coverage
output paths if supported, or by executing in a symlinked shadow tree).

Each subprocess MUST run `ReTestItems.runtests` filtered by BOTH the
test file path and the item name, against a dedicated runner environment
(`scripts/TestimonialRunner/Project.toml`).

#### Scenario: Subprocess invocation
- **WHEN** `record_item(test_file, item_name)` is called
- **THEN** a subprocess is launched with `--code-coverage=user` and
  `--project=scripts/TestimonialRunner`
- **AND** ONLY the specific `@testitem` in `test_file` matching `item_name` is executed

#### Scenario: Coverage sidecar parsing
- **WHEN** the subprocess exits successfully
- **THEN** `.jl.cov` sidecar files produced by the subprocess are parsed via
  `Coverage.process_file`
- **AND** only lines with `count > 0` are recorded as hit lines
- **AND** the sidecar files are removed after parsing

#### Scenario: Subprocess infrastructure failure
- **WHEN** the subprocess exits with an infrastructure error code (2 or 3)
- **THEN** the recording layer SHALL retry the subprocess up to a maximum of 2 attempts
- **AND** if it fails after all retries, the failure is logged and the item is omitted from the index

#### Scenario: Subprocess test failure
- **WHEN** the subprocess exits with a test failure code (1)
- **THEN** the failure is logged with the item name and file
- **AND** any generated `.jl.cov` files are still parsed and coverage is recorded (the item is treated as recorded but failing)

#### Scenario: Subprocess timeout
- **WHEN** a subprocess exceeds `timeout_per_item_seconds` (default 300 s)
- **THEN** it is killed, and the recording layer SHALL retry the subprocess up to a maximum of 2 attempts, doubling the timeout on retry
- **AND** if it times out after all retries, the failure is logged and all `.jl.cov` sidecar files for that item are deleted before recording continues

### Requirement: [REC-003] Per-item cache
The system SHALL skip re-recording a test item when a cached record exists
for its cache key (`file_hash * "_" * item_name`) in `.testimonial/items/`.

#### Scenario: Cache hit
- **WHEN** `record_all` is invoked and a valid cache record exists for an item
- **THEN** the subprocess is not spawned for that item
- **AND** the cached `ItemCoverage` is used directly in index construction

#### Scenario: Cache miss on file change
- **WHEN** a test file's content changes between recording runs
- **THEN** all items in that file have new cache keys (new `file_hash`)
- **AND** those items are re-recorded

#### Scenario: Atomic per-item cache write
- **WHEN** a per-item record is written to `.testimonial/items/<key>.jls`
- **THEN** it is written to a temporary file first and then atomically renamed
  to the final path, preventing partial writes from corrupting the cache if
  two concurrent `record_all` runs collide on the same item

### Requirement: [REC-004] Parallel recording
The system SHALL record multiple test items concurrently using
`Threads.@threads` with `nthreads = CPU_THREADS ÷ 2` to leave headroom
for the spawned subprocesses.

#### Scenario: Parallel execution
- **WHEN** `record_all` is run with multiple uncached items
- **THEN** multiple subprocesses run concurrently, up to the configured
  thread count
- **AND** the total wall-clock time is less than sequential time for the
  same item set

### Requirement: [REC-005] Index construction from per-item records
The system SHALL construct a `CoverageIndex` by loading per-item records
from `.testimonial/items/` that correspond to items discovered in the
current `record_all run. Records in the cache that do not match a
currently discovered `TestItemRef` SHALL be ignored during construction.

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

### Requirement: [REC-006] record_all public API
The system SHALL expose `Testimonial.record_all(; incremental=true, force=false)`
as the primary entry point for building or updating the coverage index.

Before beginning the recording process, the system SHALL check for uncommitted changes in the git repository. If the workspace is dirty, a warning SHALL be logged and the recorded `git_sha` in the resulting index SHALL have a `-dirty` suffix appended.

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

### Requirement: [REC-007] record_item public API
The system SHALL expose `Testimonial.record_item(test_file, item_name)`
for single-item recording, primarily for debugging and interactive use.

#### Scenario: Single item record
- **WHEN** `record_item("/abs/path/test.jl", "My test")` is called
- **THEN** exactly one subprocess is spawned for that item
- **AND** the result is an `ItemCoverage` struct with the item's coverage data

### Requirement: [REC-008] ItemCoverage per-item record
The system SHALL define an `ItemCoverage` struct representing the coverage
data recorded for one `@testitem` in a single subprocess run.

Fields:
- `ref::TestItemRef` — identifies the test item
- `coverage::Dict{String, Set{Int}}` — maps absolute source file paths to the
  set of line numbers executed by this item (lines with `count > 0` in the
  `.jl.cov` sidecar)

`ItemCoverage` is the unit of per-item cache persistence: serialized to
`.testimonial/items/<key>.jls` after recording and deserialized during index
construction. It is an **internal type** and is NOT part of the public API.

#### Scenario: Coverage population
- **WHEN** a subprocess's `.jl.cov` sidecar files are parsed
- **THEN** the `coverage` dict contains exactly the files and lines where
  `count > 0` in the sidecar output

#### Scenario: Round-trip persistence
- **WHEN** an `ItemCoverage` is serialized and then deserialized
- **THEN** the result has identical `ref` and `coverage` fields

### Requirement: [REC-009] TestimonialRunner workspace member
The system SHALL provide `scripts/TestimonialRunner/` as a separate Julia
workspace member — a minimal environment containing only the dependencies
needed for subprocess recording, isolated from the main package dependencies.

`scripts/TestimonialRunner/Project.toml` SHALL declare direct dependencies on:
- `Testimonial` (the root package, added via `pkg"dev ."`)
- `ReTestItems` (for running individual test items)
- `Coverage` (for parsing `.jl.cov` sidecar files)

`scripts/TestimonialRunner/driver.jl` is the subprocess entry point. It SHALL:
1. Accept the target item name via `TESTIMONIAL_ITEM`.
2. Accept the target test file via `TESTIMONIAL_FILE`.
3. Call `ReTestItems.runtests` with filters for both `TESTIMONIAL_FILE`
   and `TESTIMONIAL_ITEM`.
4. Exit with specific status codes to classify the run outcome:
   - `0`: Success
   - `1`: Test Failed (logic error or assertion failure)
   - `2`: Internal Error (unhandled exception in driver or runner)
   - `3`: Setup Error (missing dependencies, file not found)

#### Scenario: Driver invocation
- **WHEN** a subprocess is launched with `TESTIMONIAL_ITEM="Black-Scholes call pricing"`
- **THEN** `driver.jl` runs only that named item and exits zero on success

#### Scenario: Driver on test failure
- **WHEN** the test item raises an error or assertion fails
- **THEN** `driver.jl` exits with status code 1

#### Scenario: Driver on infrastructure failure
- **WHEN** the driver encounters an unhandled exception or cannot load the test file
- **THEN** `driver.jl` exits with status code 2 or 3

### Requirement: [REC-010] Cache cleanup
Upon successful completion of an index build, the system SHALL remove any
files in `.testimonial/items/` that do not correspond to any currently
discovered `@testitem`'s cache key. This ensures the cache directory does
not grow indefinitely with orphaned records from renamed or deleted tests.

#### Scenario: Cleanup orphaned records
- **WHEN** `record_all` completes and `.testimonial/items/` contains a file
  whose key does not match any `@testitem` found in the current run
- **THEN** that file is deleted from disk
- **AND** valid cache records used in the current index are preserved

### Requirement: [REC-011] Runner decoupling
The system SHALL decouple subprocess command construction from execution
using a trait-based runner interface. This ensures the recording logic
is testable via mock runners without spawning actual processes in unit tests.

