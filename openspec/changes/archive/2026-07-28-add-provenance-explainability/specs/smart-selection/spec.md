## MODIFIED Requirements

### Requirement: [CI-003] ImpactResult and ImpactReason types (with reason chains)

The `ImpactResult` SHALL include an optional `chain::Vector{ProvenanceLink}` field that traces the selection path from changed content unit to test item. Each `ProvenanceLink` SHALL contain the source analysis layer, the content unit, and a human-readable description.

`ProvenanceLink` fields:
- `layer::LayerKind` — one of `COVERAGE`, `INFERRED`, `STATIC`, `TEST_FILE_CHANGED`, `MANUAL`
- `content_unit::String` — normalized file path or method name
- `detail::String` — human-readable description (e.g., "function `foo()` called at line 42")
- `next::Union{Nothing, ProvenanceLink}` — the next link in the chain, forming a linked list

#### Scenario: Reason chain in ImpactResult
- **GIVEN** a test selected because changed line 47 in `src/bs.jl` is covered by the test
- **WHEN** its `ImpactResult` is inspected
- **THEN** the chain SHALL contain at least one link: `{layer=COVERAGE, content_unit="src/bs.jl:47", detail="executed line 47 in bs.jl", next=nothing}`

### Requirement: [CI-003] ImpactResult and ImpactReason types (exclusion mode)

The `explain` API SHALL support an `exclude` mode that reports why a specific test was NOT selected. The reason SHALL be derived from the index state and diff, not stored.

#### Scenario: Test not selected — no coverage overlap
- **GIVEN** a test in the index that covers files not in the changed set
- **WHEN** `explain("test.jl", "My test"; exclude=true)` is called
- **THEN** the response SHALL include "no changed file touches any covered line"
- **AND** SHALL list the files the test covers and the files in the changed set