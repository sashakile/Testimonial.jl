## ADDED Requirements

### Requirement: [SAFE-001] Over-approximation invariant

The system SHALL maintain the invariant that the modeled dependency relation over-approximates the true semantic dependency relation, such that any test that could be affected by a code change is selected. A missed selection is a bug.

#### Scenario: Soundness guarantee
- **WHEN** a code change semantically affects a test item
- **THEN** the selection SHALL include that test item
- **AND** an omission SHALL be treated as a bug requiring incident recording

### Requirement: [SAFE-002] Always-run set

The system SHALL include in the always-run set every test that failed in its last recorded run, every newly added test, every test with no recorded history, and every quarantined test. Tests in the always-run set SHALL be unconditionally selected regardless of change-based selection.

#### Scenario: Always-run composition
- **GIVEN** a test that failed in its last run, a newly added test, a test with no recording history, and a quarantined test
- **WHEN** `smart_run` computes selection
- **THEN** all four tests SHALL be in the selected set
- **AND** they SHALL be selected regardless of whether they cover any changed line

#### Scenario: Always-run eviction
- **GIVEN** a test in the always-run set that has passed in its last N consecutive runs
- **WHEN** the next selection is computed
- **THEN** the test SHALL be removed from the always-run set automatically
- **AND** N SHALL be configurable (default: 3)

### Requirement: [SAFE-003] Scoped fallback on unresolved analysis

When an analysis layer cannot determine dependencies for changed content (e.g., unresolved files in static analysis, or coverage gaps below threshold), the system SHALL fall back to a more conservative selection for that component rather than the full suite.

**Before `add-component-boundary` is implemented:** scoped fallback degrades to global fallback (all components fall back to a full run).

#### Scenario: Unresolved file fallback
- **GIVEN** a changed file that no analysis layer can model
- **WHEN** `smart_run` computes selection
- **THEN** the affected component SHALL fall back to running all tests in that component
- **AND** components with fully-resolved dependencies SHALL NOT be affected

#### Scenario: Pre-component-boundary degradation
- **GIVEN** `add-component-boundary` is not yet implemented (no component graph exists)
- **WHEN** a changed file cannot be modeled
- **THEN** all components SHALL fall back to a full run
- **AND** a warning SHALL be logged indicating that component scoping requires the component boundary feature

### Requirement: [SAFE-004] Environment change fallback

When the project environment changes (e.g., `Project.toml`, `Manifest.toml`, Julia version), the system SHALL fall back to running the full test suite for the affected environment.

#### Scenario: Manifest change
- **GIVEN** a change to `Manifest.toml`
- **WHEN** `smart_run` is invoked
- **THEN** the full test suite SHALL run for the affected environment

#### Scenario: Julia version change
- **GIVEN** the index's `julia_version` differs from the current `VERSION`
- **WHEN** `smart_run` is invoked
- **THEN** the full test suite SHALL run
- **AND** a warning SHALL be logged explaining the mismatch

### Requirement: [SAFE-005] Missed-selection incident recording

When a full run reveals a test failure that the most recent selection would have skipped, the system SHALL record a candidate missed-selection incident. A candidate incident SHALL be promoted to a permanent `manual` edge (forcing selection of that test when the implicated content unit changes) only after confirmation — either human review, or the same failure is observed across multiple independent changes.

#### Scenario: Candidate incident on full-run cross-check
- **GIVEN** a full run that fails a test
- **WHEN** that test was not in the most recent selection
- **THEN** a candidate missed-selection incident SHALL be recorded
- **AND** the incident SHALL include the changed content unit, the missed test, and a timestamp
- **AND** the incident SHALL NOT create a manual edge until confirmed

#### Scenario: Incident promotion after confirmation
- **GIVEN** a candidate incident for a (content_unit, test) pair
- **WHEN** the same failure is observed across 3 independent changes
- **THEN** the incident SHALL be promoted to a permanent manual edge
- **AND** the edge SHALL persist across index rebuilds

#### Scenario: Incident resolution
- **GIVEN** a candidate incident for a (content_unit, test) pair
- **WHEN** a human reviews and dismisses the incident (e.g., the failure was infrastructure-related)
- **THEN** the incident SHALL be discarded
- **AND** no manual edge SHALL be created

### Requirement: [SAFE-006] Must-run rules

The system SHALL support user-defined must-run rules that force-select tests when matching file patterns change. Rules SHALL be specified in `Testimonial.toml` as glob pattern → test tag or test name mappings.

#### Scenario: Must-run pattern match
- **GIVEN** a must-run rule mapping `src/infra/*.jl` to `tags=[:integration]`
- **WHEN** a file matching `src/infra/*.jl` changes
- **THEN** all tests tagged `:integration` SHALL be selected

#### Scenario: Must-run rule with scoped fallback priority
- **GIVEN** a must-run rule applies to a file, AND the same component also has unresolved files triggering scoped fallback (SAFE-003)
- **WHEN** `smart_run` computes selection
- **THEN** the scoped fallback SHALL take priority (full component run)
- **AND** the must-run reason SHALL be logged for transparency

### Requirement: [SAFE-007] Flaky detection and quarantine

When a test produces inconsistent outcomes across retried attempts in one run, the system SHALL record the outcome as flaky and update its flakiness score. A quarantined test SHALL still be selected and run, but its outcome SHALL NOT affect pass/fail trust calculations.

#### Scenario: Inconsistent outcomes
- **GIVEN** a test with differing pass/fail outcomes across retries in one run
- **WHEN** results are ingested
- **THEN** the outcome SHALL be recorded as flaky
- **AND** the test's flakiness score SHALL be updated

#### Scenario: Quarantined test semantics
- **GIVEN** a quarantined test
- **WHEN** selection is computed
- **THEN** the test SHALL be selected and run
- **BUT** its outcome SHALL NOT contribute to commit pass/fail status

#### Scenario: Flaky test runtime edge exclusion
- **GIVEN** a test marked flaky (SAFE-007)
- **WHEN** runtime feedback ingestion runs (FEED-002)
- **THEN** runtime edges from that test SHALL NOT be ingested until the test is no longer flaky
- **AND** a warning SHALL be logged

### Requirement: [SAFE-008] Shadow mode

The system SHALL support a shadow mode in which selection is computed but all tests are executed. The selection results SHALL be logged and compared against full-run outcomes. Shadow mode SHALL NOT gate test execution.

#### Scenario: Shadow mode operation
- **GIVEN** `smart_run(shadow=true)` is invoked
- **WHEN** selection is computed
- **THEN** all tests SHALL be executed regardless of selected set
- **AND** the selected set SHALL be logged alongside full-run results
- **AND** any test that would have been skipped but actually failed SHALL be recorded as a candidate missed-selection incident

#### Scenario: Shadow mode output
- **GIVEN** a shadow-mode run completes
- **WHEN** the log is inspected
- **THEN** it SHALL show: total tests, selected count, skipped count, and any candidate incidents

### Requirement: [SAFE-009] Full-run reconciliation

The system SHALL support a reconciliation workflow that runs all tests, computes the counterfactual selection, and records any candidate missed-selection incidents. This SHALL operate as a scheduled workflow (e.g., nightly) independent of per-PR `smart_run`.

#### Scenario: Reconciliation run
- **GIVEN** a scheduled reconciliation run (e.g., nightly)
- **WHEN** it completes
- **THEN** the selection that would have been made SHALL be compared against full-run results
- **AND** any candidate missed-selection incidents SHALL be recorded (see SAFE-005)
- **AND** the reconciliation report SHALL be persisted for the promotion gate

#### Scenario: Reconciliation as periodic full-run
- **GIVEN** a configured reconciliation interval (default: 24 hours)
- **WHEN** the schedule triggers
- **THEN** all tests SHALL be selected and run
- **AND** the counterfactual selection SHALL be computed and compared

### Requirement: [SAFE-010] Seeded-fault recall test

The system SHALL be verifiable by a seeded-fault recall test in which every seeded regression's fault-revealing test is selected. A seeded regression is a deliberately introduced code change whose fault-revealing test is known.

#### Scenario: Seeded fault evaluation
- **GIVEN** a set of seeded regressions with known fault-revealing tests
- **WHEN** selection is computed for each regression
- **THEN** every fault-revealing test SHALL be selected
- **AND** any missed selection SHALL be recorded as a soundness violation
- **AND** the script SHALL exit non-zero on any violation

### Requirement: [SAFE-011] Promotion protocol

The system SHALL define a promotion protocol with three stages:
1. **Shadow mode**: compute selections but don't gate; record incidents (SAFE-008).
2. **Evaluation window**: a configurable period (default: 7 days or 100 PRs) during which zero candidate missed-selection incidents must be recorded. The window SHALL run in shadow mode (all tests executed) so the metric is "would a failing test have been selected?" — not "did any test fail?"
3. **Enforcing mode**: selections gate test execution.

Promotion from shadow to enforcing SHALL require zero candidate missed-selection incidents during the evaluation window.

#### Scenario: Promotion to enforcing
- **GIVEN** a shadow-mode deployment with zero candidate incidents over the evaluation window
- **WHEN** the window completes
- **THEN** enforcing mode MAY be enabled
- **AND** if any incident occurred, enforcing mode SHALL remain disabled

#### Scenario: Regressing from enforcing to shadow
- **GIVEN** an enforcing-mode deployment
- **WHEN** a missed-selection incident is detected (via reconciliation or user report)
- **THEN** the system SHOULD recommend regressing to shadow mode
- **AND** the incident SHALL be resolved before re-enabling enforcement