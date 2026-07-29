## ADDED Requirements

### Requirement: [CI-001] CoverageIndex data model (confidence metadata)

The `CoverageIndex` struct SHALL include the following metadata fields for confidence computation:
- `built_at::DateTime` — already present in Phase 1, used for freshness signal
- `failed_item_count::Int` — already present in Phase 1, used for recording quality
- `total_discovered_items::Int` — already present in Phase 1, used for recording quality

No new fields are required for confidence scoring in Phase 1. Confidence is computed at query time from existing metadata.

#### Scenario: Confidence metadata availability
- **GIVEN** a `CoverageIndex` with `built_at`, `failed_item_count`, and `total_discovered_items`
- **WHEN** confidence is computed
- **THEN** the freshness signal uses `built_at`
- **AND** the recording quality signal uses `failed_item_count` / `total_discovered_items`