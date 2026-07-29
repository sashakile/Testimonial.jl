## 1. Confidence score computation
- [x] 1.1 Implement `compute_confidence(test_ref, index)` function
- [x] 1.2 Implement freshness signal from `index.built_at`
- [x] 1.3 Implement recording quality signal from `index.failed_item_count` / `index.total_discovered_items`
- [x] 1.4 Implement layer coverage signal (1 layer = 0.5, 2 = 0.67, 3 = 0.75)
- [x] 1.5 Implement history quality signal from `run_history.jls` (1.0 if no history)

## 2. Per-component confidence aggregation
- [x] 2.1 Group selected items by component (requires `add-component-boundary`)
- [x] 2.2 Compute per-component minimum confidence
- [x] 2.3 Integrate with `smart_run` fallback decision logic

## 3. Confidence reporting
- [x] 3.1 Show per-test confidence in dry-run output
- [x] 3.2 Show per-component minimum confidence in `smart_run` summary
- [x] 3.3 Include confidence in `explain` output
- [x] 3.4 Document that confidence is a fallback gate, not a correctness probability

## 4. Configuration
- [x] 4.1 Add `confidence_threshold` to the `Testimonial.toml` schema (per-component override)
- [x] 4.2 Add `stale_threshold_hours` to config (default: 48)
- [x] 4.3 **(depends on:** `implement-coverage-layer` Phase 3 config capability)