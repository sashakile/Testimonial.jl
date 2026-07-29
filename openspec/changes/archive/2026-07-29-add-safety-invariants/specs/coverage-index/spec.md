## ADDED Requirements

### Requirement: [CI-001] CoverageIndex data model (manual edges)

The `CoverageIndex` struct SHALL include a `manual_edges::Dict{String, Set{TestItemRef}}` field for manually confirmed missing-selection edges. When an incident is promoted to a manual edge (per SAFE-005), it SHALL be recorded here and persist across index rebuilds.

#### Scenario: Manual edge persistence
- **GIVEN** a promoted manual edge from content unit `src/core.jl` to test `"Core test"`
- **WHEN** the index is serialized and deserialized
- **THEN** the manual edge SHALL be present in `manual_edges`
- **AND** `smart_run` SHALL select `"Core test"` when `src/core.jl` changes