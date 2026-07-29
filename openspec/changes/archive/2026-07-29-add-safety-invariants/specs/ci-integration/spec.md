## ADDED Requirements

### Requirement: [CI-INT-011] Incident detection

The CI integration SHALL detect missed-selection incidents by comparing full-run results against the counterfactual selection. When a full run reveals a test failure that selection would have skipped, a candidate incident SHALL be recorded and reported.

#### Scenario: Incident detection in CI
- **GIVEN** a scheduled full run (e.g., nightly)
- **WHEN** a test fails that the most recent selection would have skipped
- **THEN** a candidate missed-selection incident SHALL be recorded
- **AND** the incident SHALL be reported in the CI output

### Requirement: [CI-INT-012] Reconciliation pipeline

The CI integration SHALL support a scheduled reconciliation pipeline that runs all tests, computes the counterfactual selection, and persists a reconciliation report.

#### Scenario: Scheduled reconciliation
- **GIVEN** a configured reconciliation interval (default: 24 hours)
- **WHEN** the schedule triggers
- **THEN** all tests SHALL be selected and run
- **AND** the counterfactual selection SHALL be computed and compared
- **AND** any candidate incidents SHALL be recorded