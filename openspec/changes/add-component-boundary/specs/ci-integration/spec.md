## ADDED Requirements

### Requirement: [CI-INT-010] Duration-balanced shard plan

When sharding is requested, the system SHALL emit a balanced shard plan computed over recorded test durations. Each shard SHALL contain tests with approximately equal total expected duration.

#### Scenario: Shard plan output
- **GIVEN** a request for sharding (e.g., `--shards 4`)
- **WHEN** `smart_run` computes selection
- **THEN** selected tests SHALL be assigned to N shards by greedy duration-balancing
- **AND** each shard SHALL have approximately equal total expected duration