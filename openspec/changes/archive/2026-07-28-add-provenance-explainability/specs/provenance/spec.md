## ADDED Requirements

### Requirement: [PROV-001] Reason chains for selected tests

The `ImpactReason` SHALL include an optional `chain::Vector{ProvenanceLink}` field that traces the selection path from changed content unit to test item. Each `ProvenanceLink` SHALL contain the source analysis layer, the content unit, and a human-readable description.

`ProvenanceLink` fields:
- `layer::LayerKind` — one of `COVERAGE`, `INFERRED`, `STATIC`, `TEST_FILE_CHANGED`, `MANUAL`
- `content_unit::String` — normalized file path or method name
- `detail::String` — human-readable description (e.g., "function `foo()` called at line 42")
- `next::Union{Nothing, ProvenanceLink}` — the next link in the chain, forming a linked list

#### Scenario: Reason chain selection
- **GIVEN** a test selected because changed line 47 in `src/bs.jl` is covered by the test
- **WHEN** its `ImpactResult` is inspected
- **THEN** the chain SHALL contain at least one link: `{layer=COVERAGE, content_unit="src/bs.jl:47", detail="executed line 47 in bs.jl", next=nothing}`

#### Scenario: Multi-hop chain
- **GIVEN** a test selected via inference edge through a chain of method calls
- **WHEN** its `ImpactResult` is inspected
- **THEN** the chain SHALL contain multiple links tracing the call path from the changed method to the test

### Requirement: [PROV-002] Exclusion reasoning

The `explain` API SHALL support an `exclude` mode that reports why a specific test was NOT selected. The reason SHALL be derived from the index state and diff, not stored.

#### Scenario: Test not selected — no coverage overlap
- **GIVEN** a test in the index that covers files not in the changed set
- **WHEN** `explain("test.jl", "My test"; exclude=true)` is called
- **THEN** the response SHALL include "no changed file touches any covered line"
- **AND** SHALL list the files the test covers and the files in the changed set

#### Scenario: Test not selected — test not in index
- **GIVEN** a test not present in the current index
- **WHEN** `explain("test.jl", "New test"; exclude=true)` is called
- **THEN** the response SHALL indicate "test has never been recorded"
- **AND** SHALL suggest running `record_all` first

#### Scenario: Test not selected — different component
- **GIVEN** a test in component B, with no dependency path from changed component A to B
- **WHEN** `explain("test.jl", "My test"; exclude=true)` is called
- **THEN** the response SHALL indicate "no dependency path from changed component to this test's component"

### Requirement: [PROV-003] Persisted provenance

The system SHALL persist the provenance of each selection so that a past selection can be re-explained without re-running the query. Provenance SHALL be stored at `.testimonial/provenance/<run_key>.jls` and SHALL be pruned after N runs (configurable, default: keep last 10).

A run key SHALL be generated for every `smart_run` invocation, regardless of whether ingest is enabled. If ingest is disabled, the provenance record SHALL still be persisted with the selection metadata but without runtime edge data.

#### Scenario: Historical explanation
- **GIVEN** a past selection with persisted provenance
- **WHEN** `explain` is called for a test in that selection
- **THEN** the response SHALL be returned from the persisted provenance
- **AND** the query SHALL NOT be re-run

#### Scenario: Provenance without ingest
- **GIVEN** a `smart_run` with `auto_ingest=false`
- **WHEN** selection completes
- **THEN** a run key SHALL be generated
- **AND** the provenance record SHALL be persisted with selection metadata
- **BUT** without runtime edge data
- **AND** `explain` SHALL fall back to re-running the query if the provenance record lacks runtime edges
- **GIVEN** more than N persisted provenance runs
- **WHEN** a new selection is computed
- **THEN** the oldest provenance run SHALL be pruned

### Requirement: [PROV-004] Layered provenance view

When multiple analysis layers contribute to a test's selection, the `explain` output SHALL group reasons by layer and show how the layers interact.

#### Scenario: Multi-layer explanation
- **GIVEN** a test selected by both coverage and static analysis layers
- **WHEN** `explain` is called
- **THEN** the output SHALL group reasons by layer (e.g., "Coverage: line 47", "Static: method `foo()`")
- **AND** SHALL indicate which layers could independently select the test