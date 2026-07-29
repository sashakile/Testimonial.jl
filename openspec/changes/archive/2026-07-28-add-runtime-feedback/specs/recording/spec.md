## ADDED Requirements

### Requirement: [REC-012] Ingest mode

The recording layer SHALL support an ingest mode that updates the existing index with new runtime data without a full rebuild. This operates as a delta update: new (file, line) → test item mappings are merged into `line_to_tests`, and `test_to_lines` is extended with any new coverage.

#### Scenario: Ingest after partial run
- **GIVEN** an existing `CoverageIndex` and a test run that exercised new lines
- **WHEN** ingestion is performed
- **THEN** the new lines SHALL be added to the index
- **AND** existing mappings SHALL NOT be affected
- **AND** the index SHALL be persisted atomically after ingestion