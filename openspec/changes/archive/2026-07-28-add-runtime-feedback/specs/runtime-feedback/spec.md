## ADDED Requirements

### Requirement: [FEED-001] Post-run ingestion

The system SHALL ingest coverage and execution data after `smart_run` completes its test execution, updating the index with new runtime edges and run history.

#### Scenario: Coverage ingestion after run
- **GIVEN** a `smart_run` that completed with selected tests executed
- **WHEN** post-run ingestion runs
- **THEN** coverage sidecar files from the test run SHALL be parsed
- **AND** new (file, line) → test item mappings SHALL be merged into the index
- **AND** the index SHALL be persisted atomically after ingestion completes

#### Scenario: Empty selection still recorded
- **GIVEN** a `smart_run` that selected no tests (empty diff or no impacted items)
- **WHEN** post-run ingestion runs
- **THEN** the empty selection SHALL be recorded as a run history entry (for confidence scoring)
- **AND** coverage sidecar parsing SHALL be skipped
- **AND** the index SHALL NOT be modified

### Requirement: [FEED-002] Runtime edge creation

When ingestion discovers that a test exercised a content unit not previously linked by any static or coverage edge, the system SHALL record a new runtime edge so that the dependency becomes selectable on future changes.

#### Scenario: New runtime dependency
- **GIVEN** coverage data showing a test touched a file line not in its recorded `coverage` dict
- **WHEN** ingestion processes the data
- **THEN** a runtime edge SHALL be recorded linking the test to that content unit
- **AND** the edge SHALL be reflected in `line_to_tests` for future queries

#### Scenario: Static edge preservation
- **GIVEN** a test with a static edge to a content unit that runtime coverage did not confirm
- **WHEN** ingestion processes the data
- **THEN** the static edge SHALL NOT be removed
- **AND** both the static and runtime edges SHALL coexist

### Requirement: [FEED-003] Run history persistence

The system SHALL persist per-test run history (outcome, duration, attempt count, failure rate) independently from the main coverage index, surviving index rebuilds.

#### Scenario: History recording
- **GIVEN** a completed test run with outcome and duration
- **WHEN** ingestion is performed
- **THEN** the test's run history SHALL be updated
- **AND** the updated history SHALL be persisted to `.testimonial/run_history.jls`

#### Scenario: History lookup
- **GIVEN** a persisted run history for a test item
- **WHEN** the test's history is queried
- **THEN** the last N outcomes, mean duration, and failure rate SHALL be returned

### Requirement: [FEED-004] Idempotent ingestion

The system SHALL reject duplicate ingestion of the same run. Each run payload SHALL carry a unique run-identity key. Before performing any write, the system SHALL check whether that key has already been recorded and skip ingestion if so.

#### Scenario: Duplicate skip
- **GIVEN** a run payload with a run-identity key already recorded
- **WHEN** ingestion is attempted again
- **THEN** all writes SHALL be skipped
- **AND** the duplicate SHALL be reported

#### Scenario: Missing key rejection
- **GIVEN** a run payload without a run-identity key
- **WHEN** ingestion is attempted
- **THEN** the system SHALL reject the payload with a diagnostic

### Requirement: [FEED-005] External input recording

When a test declares external inputs (config files, environment variables, fixture files), the system SHALL record them as runtime dependencies and include them in change detection.

#### Scenario: Declared external input
- **GIVEN** a test item annotated with external input `config/app.toml`
- **WHEN** that input file changes in a diff
- **THEN** the test SHALL be selected, regardless of whether any of its recorded source lines changed

#### Scenario: Synchronous ingestion contract
- **GIVEN** `ingest()` is called after a test run
- **WHEN** the call returns
- **THEN** the caller SHALL block until ingestion completes
- **AND** the index and run history SHALL be fully persisted before the call returns
