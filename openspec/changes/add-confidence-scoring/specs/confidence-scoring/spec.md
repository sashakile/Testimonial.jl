## ADDED Requirements

### Requirement: [CONF-001] Per-test confidence score

The system SHALL compute a selection confidence in the range [0, 1] for each selected test item. The confidence SHALL be a composite of at least coverage freshness, recording quality, analysis layer coverage, and run history quality, computed as a geometric mean of the individual factors (see `design.md` for the formula). All factors SHALL be floored at 0.01 to prevent complete zeroing from minor degradation.

#### Scenario: Confidence output for selected test
- **GIVEN** a selected test item with recent coverage and good recording quality
- **WHEN** its selection confidence is computed
- **THEN** the confidence SHALL be in the range [0, 1]
- **AND** SHALL be higher than for a test with stale coverage or poor recording quality

#### Scenario: Freshness decay
- **GIVEN** an index that is N hours old
- **WHEN** confidence is computed
- **THEN** the freshness signal SHALL decay from 1.0 (at 0 hours) toward 0 (at `stale_threshold` hours)
- **AND** the default `stale_threshold` SHALL be 48 hours

### Requirement: [CONF-002] Invocation-level quality signals

The system SHALL apply per-invocation quality signals that modulate the effective confidence without mutating stored edge weights. These signals SHALL include at least coverage freshness, recording failure ratio, analysis layer availability, and run history failure rate.

#### Scenario: Invocation-level adjustment
- **GIVEN** stale coverage data, high recording failure ratio, and only the coverage layer available
- **WHEN** selection confidence is computed
- **THEN** the effective confidence SHALL be adjusted downward
- **AND** stored edge weights and index metadata SHALL remain unchanged

### Requirement: [CONF-003] Confidence threshold fallback

When the minimum confidence across reachability-selected tests in a component falls below a configured threshold, the system SHALL fall back to a full run for that component only. The default threshold SHALL be 0.7 and SHALL be configurable per component in `Testimonial.toml`.

Confidence for always-run tests SHALL be computed separately from reachability-selected tests. The per-component minimum confidence SHALL only consider reachability-selected tests for fallback gating, matching testaruda's TIA-SAFE-002 approach.

#### Scenario: Below-threshold fallback
- **GIVEN** a component where the minimum reachability-selected test confidence is 0.3
- **WHEN** `smart_run` computes the selection
- **THEN** that component SHALL fall back to a full run
- **AND** unaffected components SHALL continue using selected subsets

#### Scenario: Above-threshold no fallback
- **GIVEN** a component where all reachability-selected test confidences exceed the threshold
- **WHEN** `smart_run` computes the selection
- **THEN** no fallback SHALL be triggered for that component

### Requirement: [CONF-004] Confidence reporting

The system SHALL report the minimum and per-test confidence values in `smart_run` output, `dry_run` mode, and `explain` output. The accompanying documentation SHALL state that confidence gates fallback and is not a probabilistic correctness guarantee.

#### Scenario: Confidence in dry-run output
- **GIVEN** `smart_run(dry_run=true)` is invoked
- **WHEN** selected items are printed
- **THEN** each selected item SHALL show its confidence score
- **AND** the per-component minimum confidence SHALL be reported