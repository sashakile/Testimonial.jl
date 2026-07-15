## ADDED Requirements

### Requirement: [SEL-001] Unified diff parsing
Given a git reference range, the system SHALL parse the unified diff into a
`Dict{String, Set{Int}}` mapping absolute source file paths (normalized via
`realpath`) to the set of changed line numbers.

Only lines in the diff context that are additions or modifications (prefixed
`+`) are counted as changed. Deletions and context lines are ignored.

Paths in the diff output are resolved to absolute form relative to the
repository root and normalized via `realpath` before insertion into the map.

#### Scenario: Manifest or Project changes
- **WHEN** a diff includes changes to `Project.toml` or `Manifest.toml`
- **THEN** `testimonial run` SHALL fall back to running the full test suite,
  as global environment changes invalidate granular coverage analysis.


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

### Requirement: [SEL-002] Line-level impact query
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

### Requirement: [SEL-003] File-level coarse query
The system SHALL implement `Testimonial.query_files(changed_files::Vector{String})`
that selects any test item that covered any line of the given files.

#### Scenario: File-level query
- **WHEN** `query_files(["src/foo.jl"])` is called
- **THEN** every test item that covered at least one line in `foo.jl` is returned

### Requirement: [SEL-004] Coverage gap detection
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

### Requirement: [SEL-005] testimonial run — standalone selection pipeline
The system SHALL implement `Testimonial.run(; base_ref="origin/main", dry_run=false)`
that:

1. If the diff includes changes to `Project.toml` or `Manifest.toml`, emit
   "Environment change detected — running full suite" and fall back to
   running the full test suite. (Checked first because environment changes
   invalidate all coverage analysis.)
2. Loads the `CoverageIndex` from `.testimonial/index.jls`. If the index does
   not exist, emit "No coverage index found — run `testimonial record` first to
   enable selective runs" and fall back to running the full test suite. If the
   index is stale (more than `STALE_INDEX_THRESHOLD_HOURS` old, or `julia_version`
   mismatch), emit "Coverage index is stale — running full suite" and fall back
   to running the full test suite.
3. Runs `git diff --unified=0 <base_ref>...HEAD` and parses the result.
4. If the diff is empty (no changed `.jl` files), logs a message and returns
   successfully without invoking `runtests`.
5. Calls `query` to get impacted test items.
6. If any `CoverageGap` exists (changed lines with no recorded coverage), emit
   a warning listing the uncovered files and fall back to running the full test
   suite. (No gap policy dispatch — the conservative fallback always applies.)
   Note: only lines that are additions or modifications (per SEL-001) are
   checked for gaps. Deletions-only diffs produce no gaps and proceed normally.te.
7. If `dry_run=true`: prints selected items with their reasons and returns
   without executing tests.
8. Otherwise: invokes `ReTestItems.runtests` with `name` filter set to the
   selected item names. When multiple items share the same name across
   different test files, both are run; this minor over-selection is acceptable
   in Phase 1.

The system SHALL NOT implement gap policies, max-selection caps, or staleness
warnings that proceed with selective runs. The only response to any uncertainty
(stale index, missing index, coverage gaps, environment changes) is: run the
full test suite. This is intentionally conservative — it's simpler and harder

to get wrong than a policy layer.

#### Scenario: Normal PR with coverage
- **WHEN** `testimonial run` is called on a branch with changes covered by the index
- **THEN** only the impacted test items run
- **AND** the full test suite is not invoked

#### Scenario: Dry run output
- **WHEN** `testimonial run(dry_run=true)` is called
- **THEN** selected items and their reasons are printed to stdout
- **AND** no tests are executed

#### Scenario: Coverage gap, conservative fallback
- **WHEN** changed lines have no recorded coverage
- **THEN** a warning is emitted listing the uncovered files and lines
- **AND** the full test suite is run instead of the selective set

#### Scenario: Index missing
- **WHEN** `.testimonial/index.jls` does not exist
- **THEN** "No coverage index found" message is emitted
- **AND** the full test suite is run

#### Scenario: Stale index
- **WHEN** the index `built_at` is more than `STALE_INDEX_THRESHOLD_HOURS`
  before the current time
- **THEN** "Coverage index is stale" message is emitted
- **AND** the full test suite is run

#### Scenario: Empty diff (no changed Julia files)
- **WHEN** `git diff` returns no changed `.jl` files (branch is clean or all
  changes are in non-Julia files)
- **THEN** `testimonial run` completes successfully without invoking `runtests`
- **AND** a message is logged indicating that no Julia changes were detected

#### Scenario: Git command failure
- **WHEN** the `git` command is not found or returns a non-zero exit code (e.g.,
  invalid `base_ref`, not a git repository)
- **THEN** `testimonial run` raises a human-readable error explaining the failure
- **AND** no tests are executed

### Requirement: [SEL-006] explain API
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

### Requirement: [SEL-007] index_info API
The system SHALL implement `Testimonial.index_info()` that returns a
`NamedTuple` with index metadata for inspection.

Fields: `git_sha`, `julia_version`, `built_at`, `schema_version`,
`item_count` (number of distinct `TestItemRef`s with successful coverage), `file_count` (number of
source files with coverage entries), `age_hours` (hours since `built_at`),
`total_discovered_items` (total `@testitem` blocks found), and `failed_item_count`
(number of items that failed to record).

#### Scenario: Index info report
- **WHEN** `index_info()` is called with a valid index on disk
- **THEN** the returned named tuple contains correct values for all fields

