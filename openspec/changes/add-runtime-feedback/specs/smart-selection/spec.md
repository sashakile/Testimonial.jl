## MODIFIED Requirements

### Requirement: [SMART-002] smart_run orchestration (with ingest)

After test execution completes, `smart_run` SHALL invoke the ingestion phase to feed back coverage data, runtime edges, and run history. The ingestion phase SHALL run synchronously — the caller SHALL block until ingestion completes and the index is fully persisted.

#### Scenario: Post-run ingestion in smart_run
- **GIVEN** a `smart_run` that completed with selected tests executed
- **WHEN** post-run ingestion runs
- **THEN** coverage sidecar files from the test run SHALL be parsed
- **AND** new (file, line) → test item mappings SHALL be merged into the index
- **AND** the index SHALL be persisted atomically after ingestion completes

#### Scenario: Empty selection still recorded
- **GIVEN** a `smart_run` that selected no tests (empty diff or no impacted items)
- **WHEN** post-run ingestion runs
- **THEN** the empty selection SHALL be recorded as a run history entry
- **AND** coverage sidecar parsing SHALL be skipped
- **AND** the index SHALL NOT be modified