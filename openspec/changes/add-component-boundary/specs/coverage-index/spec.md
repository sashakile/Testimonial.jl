## MODIFIED Requirements

### Requirement: [CI-001] CoverageIndex data model (component-scoped)

The CoverageIndex struct SHALL remain as defined in `implement-coverage-layer` with the following additions: a `component::String` field SHALL be added to scope the index to a single component. The top-level index SHALL be stored per-component under `.testimonial/components/<component_name>/`, and `.testimonial/index.jls` SHALL become a routing file enumerating available components.

#### Scenario: Per-component index storage
- **GIVEN** a `CoverageIndex` that was recorded for component `lib_a`
- **WHEN** the index is persisted
- **THEN** it SHALL be written to `.testimonial/components/lib_a/index.jls`
- **AND** the routing file `.testimonial/index.jls` SHALL include `lib_a` in its component list

### Requirement: [CI-002] TestItemRef identity type (component-aware)

TestItemRef SHALL gain a `component::String` field identifying which Julia workspace component the test belongs to. The `component` field SHALL be included in `==` and `hash`.

#### Scenario: Component-aware identity
- **GIVEN** two `TestItemRef` values with the same `test_file` and `item_name` but different `component`
- **WHEN** compared
- **THEN** they SHALL NOT be equal
