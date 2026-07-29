## ADDED Requirements

### Requirement: [CI-001] CoverageIndex data model (provenance persistence)

The `CoverageIndex` SHALL NOT store provenance data directly. Instead, provenance SHALL be persisted separately at `.testimonial/provenance/<run_key>.jls`, independent of the coverage index. Run keys SHALL be generated for every `smart_run` invocation. Provenance records SHALL be pruned after N runs (configurable, default: keep last 10).

#### Scenario: Historical explanation
- **GIVEN** a past selection with persisted provenance
- **WHEN** `explain` is called for a test in that selection
- **THEN** the response SHALL be returned from the persisted provenance
- **AND** the query SHALL NOT be re-run

#### Scenario: Provenance pruning
- **GIVEN** more than N persisted provenance runs
- **WHEN** a new selection is computed
- **THEN** the oldest provenance run SHALL be pruned