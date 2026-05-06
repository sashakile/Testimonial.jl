## ADDED Requirements

### Requirement: [CI-001] CoverageIndex data model
The system SHALL define a `CoverageIndex` struct that stores the mapping
between source lines and test items in both directions, along with metadata
for cache invalidation.

Fields:
- `line_to_tests::Dict{String, Dict{Int, Vector{TestItemRef}}}` — source file →
  line → test items that executed that line (primary query direction).
  Keys MUST be normalized via `realpath`.
- `test_to_lines::Dict{TestItemRef, Dict{String, Set{Int}}}` — test item →
  source files → lines covered (reverse index for explain and incremental recording).
  Source file keys MUST be normalized via `realpath`.
- `inference_edges::Dict{String, Set{TestItemRef}}` — reserved for Phase 2;
  initialized as empty dict in Phase 1
- `static_edges::Dict{String, Set{TestItemRef}}` — reserved for Phase 3;
  initialized as empty dict in Phase 1
- `git_sha::String` — commit SHA at which this index was recorded
- `julia_version::String` — Julia version string; index treated as stale on mismatch
- `built_at::DateTime` — UTC timestamp of index construction
- `schema_version::Int` — bumped on breaking struct changes; current value is 1
- `total_discovered_items::Int` — total number of `@testitem` blocks found during the scan
- `failed_item_count::Int` — number of items that failed to record (due to crash or timeout)

The constant `Testimonial.SCHEMA_VERSION::Int` SHALL be set to `1` and
incremented on any breaking change to `CoverageIndex`. It is the source of
truth for the schema check on index load.

The constant `Testimonial.DEFAULT_MAX_SELECTED_ITEMS::Int` SHALL be set to `200`
and used by `smart_run` to determine when to fall back to a full test run.

#### Scenario: Forward query
- **WHEN** a source file and line number are looked up in `line_to_tests`
- **THEN** the result is a `Vector{TestItemRef}` of all items that executed that line
- **AND** the lookup is O(1) in the number of source files

#### Scenario: Reverse query
- **WHEN** a `TestItemRef` is looked up in `test_to_lines`
- **THEN** the result maps each source file to the set of lines the item covered

#### Scenario: Schema version mismatch
- **WHEN** a persisted index is loaded and `schema_version != SCHEMA_VERSION`
- **THEN** the index is rejected and recording is re-triggered

#### Scenario: Julia version mismatch
- **WHEN** a persisted index is loaded and `julia_version != string(VERSION)`
- **THEN** the index is treated as stale and recording is re-triggered

### Requirement: [CI-002] TestItemRef identity type
The system SHALL define a `TestItemRef` struct that uniquely identifies a
`@testitem` within the monorepo.

Fields:
- `test_file::String` — absolute path to the test file, normalized via `realpath`.
- `item_name::String` — the string literal passed to `@testitem`.
- `tags::Vector{Symbol}` — the `tags=[...]` declaration (empty if omitted).
- `file_hash::String` — SHA-256 prefix (12 hex chars) of test file raw bytes
  at recording time; used for cache key computation.

`TestItemRef` SHALL implement `==` and `hash` based ONLY on `test_file` and
`item_name`. The `file_hash` and `tags` fields MUST be excluded from equality
and hashing to ensure the identity of a test item persists even when its
content or tags change.

#### Scenario: Equality and hashing
- **WHEN** two `TestItemRef` values have identical `test_file` and `item_name` but different `file_hash`
- **THEN** they compare equal and produce the same hash
- **AND** they can be used interchangeably as dict keys

#### Scenario: Cache key derivation
- **WHEN** a cache key is computed for a test item
- **THEN** the key is `file_hash * "_" * item_name` (hex prefix concatenated with name)

### Requirement: [CI-003] ImpactResult and ImpactReason types
The system SHALL define `ImpactResult` and `ImpactReason` types that explain
why a test item was selected, enabling developer inspection and debugging.

`ImpactResult` fields:
- `test_ref::TestItemRef`
- `reasons::Vector{ImpactReason}` — at least one entry per selected item

`ImpactReason` fields:
- `kind::ImpactReasonKind` — one of `COVERED_LINE`, `INFERRED_CALL`,
  `STATIC_CALL`, `TEST_FILE_CHANGED`
- `source_file::String`
- `detail::String` — human-readable explanation (e.g., "executed line 47")

#### Scenario: Explainable selection
- **WHEN** a test item is selected by `query`
- **THEN** its `ImpactResult.reasons` is non-empty
- **AND** each reason identifies the source file and a human-readable detail

#### Scenario: Test file change reason
- **WHEN** a test file itself is in the changed set
- **THEN** all `@testitem`s in that file are selected with `kind = TEST_FILE_CHANGED`

### Requirement: [CI-004] CoverageGap type
The system SHALL define a `CoverageGap` struct that identifies changed source
lines with no recorded coverage in any layer.

Fields:
- `source_file::String` — absolute path
- `uncovered_lines::Vector{Int}` — changed lines with no coverage entry
- `nearest_covered_lines::Vector{Int}` — up to 5 covered lines nearest (by
  line number distance) to the uncovered lines in the same source file, for
  context

#### Scenario: Gap detection
- **WHEN** a changed line has no coverage entry in `line_to_tests` or any other
  analysis layer registered in `layer_data`
- **THEN** it appears in the `uncovered_lines` of a `CoverageGap` for that file

### Requirement: [CI-005] Index persistence
The system SHALL persist the `CoverageIndex` at `.testimonial/index.jls` using
Julia's `Serialization` module, and per-item records at
`.testimonial/items/<key>.jls`.

#### Scenario: Round-trip persistence
- **WHEN** a `CoverageIndex` is serialized and then deserialized
- **THEN** the result is equal to the original (same fields, same values)

#### Scenario: Atomic write
- **WHEN** the index is written to disk
- **THEN** it is written to a temporary file first and then renamed to the
  final path, preventing partial writes from corrupting a valid index

#### Scenario: Corrupted index
- **WHEN** loading `.testimonial/index.jls` raises a deserialization error
  that is not a schema mismatch (e.g., truncated file from a previous
  interrupted write, disk full during write)
- **THEN** the error is caught and a human-readable message is emitted
  explaining the index is corrupt and `record_all` must be re-run
- **AND** `smart_run` raises an informative error rather than propagating a
  raw Julia exception
