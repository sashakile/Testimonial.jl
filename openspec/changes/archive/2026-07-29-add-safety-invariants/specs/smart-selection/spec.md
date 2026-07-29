## MODIFIED Requirements

### Requirement: [SMART-002] smart_run orchestration (safety-aware)

`smart_run` SHALL incorporate the following safety mechanisms into its orchestration:
1. **Always-run set**: unconditionally select tests that failed last run, are newly added, have no history, or are quarantined.
2. **Scoped fallback**: when an analysis layer cannot resolve dependencies for a component, fall back to a full run for that component only.
3. **Environment change fallback**: when `Project.toml`, `Manifest.toml`, or Julia version changes, run the full suite.
4. **Shadow mode**: when `shadow=true`, compute selection but run all tests, logging comparison results.

#### Scenario: Always-run set in smart_run
- **GIVEN** a test that failed in its last run, a newly added test, and a test with no recording history
- **WHEN** `smart_run` computes selection
- **THEN** all three tests SHALL be unconditionally selected
- **AND** they SHALL be selected regardless of whether they cover any changed line