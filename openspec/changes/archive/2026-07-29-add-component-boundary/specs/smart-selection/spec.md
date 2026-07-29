## MODIFIED Requirements

### Requirement: [SMART-001] query function (component-scoped)

The `query` function SHALL accept an optional `component` argument. When provided, the query SHALL only search that component's index. When omitted, the query SHALL search all components and return results grouped by component.

#### Scenario: Component-scoped query
- **GIVEN** a `query` call with `component="lib_a"`
- **WHEN** the query runs
- **THEN** only the `lib_a` component index SHALL be searched
- **AND** results SHALL NOT include items from other components

### Requirement: [SMART-002] smart_run orchestration (parallel per-component)

`smart_run` SHALL resolve affected components bottom-up from the change set, then run per-component selection in parallel using `Threads.@threads`. Only components that transitively depend on changed code SHALL be searched for affected tests.

#### Scenario: Bottom-up resolution
- **GIVEN** a change in component `LibA`
- **WHEN** `smart_run` computes selection
- **THEN** components depending on `LibA` SHALL be resolved at the component level
- **AND** only components that transitively depend on `LibA` SHALL be searched for affected tests

### Requirement: [SMART-003] Cached selection decisions

Per-component selection decisions SHALL be cached keyed on the component's dependency fingerprint. When the fingerprint is unchanged, the cached selection SHALL be reused.

#### Scenario: Cache reuse
- **GIVEN** a component whose dependency fingerprint matches a cached value
- **WHEN** `smart_run` computes selection
- **THEN** the cached selection result SHALL be reused
- **AND** the query computation SHALL be skipped for that component