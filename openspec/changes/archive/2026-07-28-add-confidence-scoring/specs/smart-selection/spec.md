## MODIFIED Requirements

### Requirement: [SMART-002] smart_run orchestration (confidence-aware)

`smart_run` SHALL compute per-test confidence and per-component minimum confidence during the selection phase. When a component's minimum reachability-selected confidence falls below the configured threshold, that component SHALL fall back to a full run. Unaffected components SHALL continue using selected subsets.

#### Scenario: Below-threshold fallback in smart_run
- **GIVEN** a component where the minimum reachability-selected test confidence is 0.3
- **WHEN** `smart_run` computes the selection
- **THEN** that component SHALL fall back to a full run
- **AND** unaffected components SHALL continue using selected subsets