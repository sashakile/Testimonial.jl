## ADDED Requirements

### Requirement: [COMP-001] Component-scoped index

The system SHALL maintain the `CoverageIndex` as a per-component artifact. Each component's index SHALL be stored under `.testimonial/components/<component_name>/`. The top-level `.testimonial/index.jls` SHALL become a routing file that enumerates available components.

In a single-package project (no Julia workspace), the system SHALL infer the component name from the root `Project.toml`'s `name` field and create a single degenerate component.

#### Scenario: Per-component storage
- **GIVEN** a monorepo with components `LibA`, `LibB`, and `App`
- **WHEN** `record_all` completes
- **THEN** three component indices SHALL exist under `.testimonial/components/lib_a/`, `.testimonial/components/lib_b/`, `.testimonial/components/app/`
- **AND** each index SHALL contain only the test items belonging to that component

#### Scenario: Single-package project
- **GIVEN** a project with no `[workspace]` in `Project.toml`
- **WHEN** `record_all` completes
- **THEN** the component name SHALL be inferred from `Project.toml`'s `name` field
- **AND** a single component index SHALL exist under `.testimonial/components/<name>/`

#### Scenario: Single-package project
- **GIVEN** a project with no `[workspace]` in `Project.toml`
- **WHEN** `record_all` completes
- **THEN** the component name SHALL be inferred from `Project.toml`'s `name` field
- **AND** a single component index SHALL exist under `.testimonial/components/<name>/`

### Requirement: [COMP-002] Component graph

The system SHALL maintain a component graph separate from the fine-grained coverage index. The graph records which component depends on which, at file level.

Inter-component edges SHALL be recorded as a superset of intra-component coverage: if any test in component B covers any line in component A, a component-level edge from B→A SHALL be recorded. This ensures over-approximation (no recall gap) while keeping the component graph simple.

#### Scenario: Component dependency recording
- **GIVEN** a test in component `App` that covers a line in component `LibA`
- **WHEN** the index is built
- **THEN** the component graph SHALL record a dependency edge from `App` to `LibA`

### Requirement: [COMP-003] Bottom-up resolution

When computing selection, the system SHALL first resolve affected components bottom-up from the change set, then select within each affected component.

#### Scenario: Bottom-up resolution
- **GIVEN** a change in component `LibA`
- **WHEN** `smart_run` computes selection
- **THEN** components depending on `LibA` SHALL be resolved at the component level
- **AND** only components that transitively depend on `LibA` SHALL be searched for affected tests

### Requirement: [COMP-004] Per-component cached selection

The system SHALL key a component's cached selection decision on its dependency fingerprint and SHALL reuse the cached decision when the fingerprint is unchanged.

#### Scenario: Cache reuse
- **GIVEN** a component whose dependency fingerprint matches a cached value
- **WHEN** `smart_run` computes selection
- **THEN** the cached selection result SHALL be reused
- **AND** the query computation SHALL be skipped for that component

### Requirement: [COMP-005] Parallel per-component selection

The system SHALL compute per-component selection in parallel using `Threads.@threads`.

#### Scenario: Parallel evaluation
- **GIVEN** multiple affected components
- **WHEN** `smart_run` computes selection
- **THEN** per-component selection SHALL run concurrently across available threads

### Requirement: [COMP-006] Duration-balanced shard plan

When sharding is requested, the system SHALL emit a balanced shard plan computed over recorded test durations. Each shard SHALL contain tests with approximately equal total expected duration.

#### Scenario: Shard plan output
- **GIVEN** a request for sharding (e.g., `--shards 4`)
- **WHEN** `smart_run` computes selection
- **THEN** selected tests SHALL be assigned to N shards by greedy duration-balancing
- **AND** each shard SHALL have approximately equal total expected duration