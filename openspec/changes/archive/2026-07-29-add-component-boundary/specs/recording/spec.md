## MODIFIED Requirements

### Requirement: [REC-005] Index construction from per-item records (component-scoped)

When constructing a `CoverageIndex`, the system SHALL group items by component and build one index per component. Each per-component index SHALL contain only the `TestItemRef`s that belong to that component.

#### Scenario: Per-component index construction
- **GIVEN** recorded items from components `LibA`, `LibB`, and `App`
- **WHEN** `record_all` constructs the index
- **THEN** three separate `CoverageIndex` instances SHALL be built
- **AND** each SHALL contain only the items for its component