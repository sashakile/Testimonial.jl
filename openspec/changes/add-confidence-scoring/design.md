## Context

The current stale-index heuristic is a single threshold (24-hour `built_at` age). This is coarse:

- A 2-hour-old index is treated identically to a 23-hour-old index.
- A 25-hour-old index that was recorded with 100% test success is treated identically to a 25-hour-old index with 30% failed recordings.
- An index with only the coverage layer (Phase 1) is treated identically to one with all three layers (Phase 3).

Confidence scoring makes these distinctions visible and actionable.

## Goals / Non-Goals

**Goals:**
- Per-test confidence score in [0, 1]
- Per-component minimum confidence (derived from per-test scores)
- Invocation-level quality signals that modulate confidence without mutating stored data
- Confidence-threshold fallback: configurable per-component threshold, default `0.7`

**Non-Goals:**
- Probabilistic correctness guarantees (confidence is a heuristic, not a probability)
- Viterbi path confidence over a K-relation (that's testaruda's approach — simpler heuristics suffice for Phase 1)

## Decisions

### Decision 1: Composite confidence score, not path-based
testaruda uses Viterbi path confidence (edge-weight multiplication along dependency paths). For Testimonial.jl, a simpler composite score is more appropriate: the product of independent quality signals, each in [0, 1]. This avoids introducing Datalog/K-relation infrastructure just for confidence.

Composite formula (initial draft):
```
confidence = (freshness * recording_quality * layer_coverage * history_quality)^(1/4)
```

The geometric mean ensures no single factor can zero out the score. If any factor is 0, the product is 0, but the (1/4) root preserves the relative ordering while damping extreme values. All factors are floored at 0.01 to prevent complete zeroing from minor degradation.

Where:
- `freshness` = `1 - min(age_hours / stale_threshold, 1)` (decays linearly to 0)
- `recording_quality` = `1 - (failed_items / total_items)` (fewer failures → higher quality)
- `layer_coverage` = `1 / (num_layers_available + 1)` (more layers → higher ceiling; 1 layer = 0.5, 3 = 0.75)
- `history_quality` = `1 - failure_rate` (from run history; 1.0 if no history)

The exact formula is configurable and will be tuned experimentally.

### Decision 2: Scoped per-component fallback
Each component has its own confidence threshold (default 0.7). If the *minimum* confidence across reachability-selected tests in a component falls below threshold, only that component falls back to a full run. Unaffected components keep using selected subsets.

### Decision 3: Stored edge weights are immutable
Confidence signals are computed at query time, not stored. This ensures deterministic results for the same stored data (testaruda TIA-REL-001 makes the same choice via TIA-CONF-002).

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Composite formula produces counterintuitive results | Log all component signals; expose raw factors in `index_info` |
| Threshold tuning is environment-specific | Make per-component thresholds configurable in `Testimonial.toml`; start with conservative 0.5 default |
| Confidence adds cognitive overhead for users | Include confidence in dry-run output as education; document meaning clearly |

## Open Questions

- Should confidence be computed per-test or per-component? (Proposal: per-test, aggregated per-component)
- Should the stale threshold be a hard constant or proportional to the recording interval?