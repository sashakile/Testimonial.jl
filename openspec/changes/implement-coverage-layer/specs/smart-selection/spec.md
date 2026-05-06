## ADDED Requirements

### Requirement: Unified diff parsing
The system SHALL parse the output of `git diff --unified=0 <base>...HEAD` into
a `Dict{String, Set{Int}}` mapping absolute source file paths to the set of
changed line numbers.

Only lines in the diff context that are additions or modifications (prefixed
`+`) are counted as changed. Deletions and context lines are ignored.

Paths in the diff output are resolved to absolute form relative to the
repository root before insertion into the map.

Files with extensions other than `.jl` SHALL be excluded from the changed set
and do not contribute to coverage gap detection.

#### Scenario: Non-Julia files in diff
- **WHEN** a diff includes changes to `README.md`, `Project.toml`, or other
  non-Julia files alongside `.jl` changes
- **THEN** only the `.jl` files appear in the returned map
- **AND** the non-`.jl` files do not trigger coverage gap warnings

#### Scenario: Simple diff
- **WHEN** a unified diff adds lines 10–12 in `src/foo.jl` and modifies line
  47 in `src/bar.jl`
- **THEN** the result maps each file to the correct set of changed line numbers

#### Scenario: New file
- **WHEN** a diff shows a new file with no prior content
- **THEN** all added lines in the new file appear in the changed set

#### Scenario: Deleted file
- **WHEN** a diff shows a file deletion
- **THEN** the deleted file is not included in the changed set (no lines to query)

### Requirement: Line-level impact query
The system SHALL implement `Testimonial.query(changed::Dict{String, Set{Int}})`
that returns `Vector{ImpactResult}` — the test items that cover at least one
changed line.

For each (file, lines) pair:
1. Look up each line in `index.line_to_tests[file]` and collect all matching
   `TestItemRef`s with `kind = COVERED_LINE`.
2. In Phase 1, `inference_edges` and `static_edges` are empty; no additional
   hits are generated.

The result is deduplicated: if the same `TestItemRef` appears via multiple
changed lines, its `ImpactResult` accumulates all reasons.

#### Scenario: Single changed line with coverage
- **WHEN** line 47 of `src/bs.jl` is in the changed set and the index records
  that `"Black-Scholes call pricing"` executed that line
- **THEN** `query` returns an `ImpactResult` for that item with one reason
  `{kind=COVERED_LINE, source_file=".../bs.jl", detail="executed line 47"}`

#### Scenario: Multiple changed lines, same test
- **WHEN** lines 47 and 48 both map to the same test item
- **THEN** one `ImpactResult` is returned with two `ImpactReason` entries

#### Scenario: Changed line with no coverage
- **WHEN** a changed line has no entry in the index
- **THEN** no `ImpactResult` is generated for that line
- **AND** the line contributes to a `CoverageGap`

#### Scenario: Changed test file
- **WHEN** a changed file is itself under `test_directories`
- **THEN** all `@testitem`s defined in that file are included in the result
  with `kind = TEST_FILE_CHANGED`, regardless of which lines changed

#### Scenario: Dual selection — test file changed and line covered
- **WHEN** an item's test file is in the changed set AND the item also covers
  a changed source line in a different file
- **THEN** the item is selected once (deduplicated) with both reasons present
  in `ImpactResult.reasons`: one `TEST_FILE_CHANGED` and one `COVERED_LINE`

### Requirement: File-level coarse query
The system SHALL implement `Testimonial.query_files(changed_files::Vector{String})`
that selects any test item that covered any line of the given files.

#### Scenario: File-level query
- **WHEN** `query_files(["src/foo.jl"])` is called
- **THEN** every test item that covered at least one line in `foo.jl` is returned

### Requirement: Coverage gap detection
The system SHALL implement `Testimonial.coverage_gaps(changed)` that returns
`Vector{CoverageGap}` — files and lines in the changed set with no recorded
coverage in any layer of the index.

#### Scenario: Gap on new code
- **WHEN** a PR adds a new function in `src/new.jl` with no prior coverage
- **THEN** `coverage_gaps` returns a `CoverageGap` for `new.jl` listing all
  added lines as uncovered
- **AND** `nearest_covered_lines` is empty (no adjacent covered lines exist)

#### Scenario: No gaps
- **WHEN** every changed line has at least one test item in the index
- **THEN** `coverage_gaps` returns an empty vector

### Requirement: smart_run orchestration
The system SHALL implement `Testimonial.smart_run(; base_ref="origin/main", strict_coverage=false, dry_run=false)` that:

1. Loads the `CoverageIndex` from `.testimonial/index.jls`.
2. Runs `git diff --unified=0 <base_ref>...HEAD` and parses the result.
3. If the diff is empty (no changed `.jl` files), logs a message and returns
   successfully without invoking `runtests`.
4. Calls `query` to get impacted test items.
5. Checks for coverage gaps via `coverage_gaps`.
6. Handles gaps per Phase 1 hardcoded policy (configurable in Phase 3 via
   `on_coverage_gap` config key):
   - Default (`strict_coverage=false`): adds items tagged `:fast` to the
     selected set (equivalent to `on_coverage_gap = "fallback_fast"` in Phase 3).
   - Strict (`strict_coverage=true`): raises an error listing uncovered files
     and lines (equivalent to `on_coverage_gap = "fail"` in Phase 3).
7. If the number of selected items exceeds 200 (Phase 1 hardcoded cap;
   configurable as `max_selected_items` in Phase 3), logs the reason and
   falls through to running the full test suite.
8. If `dry_run=true`: prints selected items with their reasons and returns
   without executing tests.
9. Otherwise: invokes `ReTestItems.runtests` with `name` filter set to the
   selected item names. When multiple items share the same name across
   different test files, both are run; this minor over-selection is acceptable
   in Phase 1.

`strict_coverage=true` is equivalent to `on_coverage_gap = "fail"`;
`strict_coverage=false` (default) is equivalent to `on_coverage_gap = "fallback_fast"`.

The system SHALL warn (but not fail) when the loaded index is more than
24 hours old, to alert developers that selections may be based on stale data.

#### Scenario: Normal PR with coverage
- **WHEN** `smart_run` is called on a branch with changes covered by the index
- **THEN** only the impacted test items run
- **AND** the full test suite is not invoked

#### Scenario: Dry run output
- **WHEN** `smart_run(dry_run=true)` is called
- **THEN** selected items and their reasons are printed to stdout
- **AND** no tests are executed

#### Scenario: Coverage gap, fallback_fast policy
- **WHEN** changed lines have no coverage and `strict_coverage=false` (default)
- **THEN** all items tagged `:fast` are added to the selected set
- **AND** a warning is logged identifying the uncovered files

#### Scenario: Coverage gap, strict policy
- **WHEN** changed lines have no coverage and `strict_coverage=true`
- **THEN** `smart_run` raises an error listing the uncovered files and lines
- **AND** no tests are executed

#### Scenario: Index missing
- **WHEN** `.testimonial/index.jls` does not exist
- **THEN** `smart_run` raises an informative error explaining that recording
  must be run first

#### Scenario: Stale index warning
- **WHEN** the index `built_at` is more than 24 hours before the current time
- **THEN** a warning is printed indicating the index age
- **AND** smart_run proceeds normally

#### Scenario: Empty diff (no changed Julia files)
- **WHEN** `git diff` returns no changed `.jl` files (branch is clean or all
  changes are in non-Julia files)
- **THEN** `smart_run` completes successfully without invoking `runtests`
- **AND** a message is logged indicating that no Julia changes were detected

#### Scenario: Max selection cap
- **WHEN** the number of selected items exceeds 200 (Phase 1 hardcoded cap)
- **THEN** `smart_run` logs the reason and falls through to running the full
  test suite instead of the selected subset

### Requirement: explain API
The system SHALL implement `Testimonial.explain(test_file, item_name)` that
returns the list of source files (with line ranges) that the given test item
covered, as recorded in the index.

#### Scenario: Explain a test item
- **WHEN** `explain("/path/to/test.jl", "My test")` is called
- **THEN** a list of strings is returned, each identifying a source file and
  its covered line count

#### Scenario: Unknown item
- **WHEN** the named item is not in the index
- **THEN** an empty vector is returned and a warning is logged

### Requirement: index_info API
The system SHALL implement `Testimonial.index_info()` that returns a
`NamedTuple` with index metadata for inspection.

Fields: `git_sha`, `julia_version`, `built_at`, `schema_version`,
`item_count` (number of distinct `TestItemRef`s), `file_count` (number of
source files with coverage entries), `age_hours` (hours since `built_at`).

#### Scenario: Index info report
- **WHEN** `index_info()` is called with a valid index on disk
- **THEN** the returned named tuple contains correct values for all fields
