## ADDED Requirements

### Requirement: [CI-001] CoverageIndex data model (runtime edges)

The `CoverageIndex` struct SHALL support runtime edges in addition to the existing `inference_edges` and `static_edges`. A new field `runtime_edges::Dict{String, Set{TestItemRef}}` SHALL be added, mapping content units (source file paths) to the set of test items that exercised them during runtime ingestion.

#### Scenario: Runtime edge storage
- **GIVEN** a runtime ingestion that discovered a new (file, line) → test mapping
- **WHEN** the index is updated
- **THEN** the runtime edge SHALL be stored in `runtime_edges`
- **AND** the mapping SHALL appear in `line_to_tests` for future queries