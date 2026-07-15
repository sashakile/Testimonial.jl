# Change: Add Confidence Scoring — Selection Quality Signals and Threshold-Based Fallback

> **Status (two-layer architecture): DEFERRED indefinitely.**
> Confidence scoring is a nice-to-have for standalone mode but not
> correctness-critical. The conservative fallback (run everything on uncertainty)
> covers the same gap without the complexity. In adapter mode, testaruda's own
> confidence heuristics handle this. This proposal should not be implemented
> until standalone mode has real users asking for graduated quality signals.

## Why

Testimonial.jl currently has a binary view of index quality: the index is either valid (fresh enough) or stale (24+ hours). There's no gradient between "barely confident" and "highly confident." A confidence score lets the system make graduated decisions: trade off precision for recall when confidence is low, without a hard cutoff.

## What Changes

- **Add confidence computation**: per-test selection confidence in [0, 1], derived from coverage freshness, recording completeness, run history quality, and analysis layer coverage.
- **Add invocation-level quality signals**: stale coverage reduces confidence; failed recording attempts reduce confidence; missing inference/static layers reduce confidence.
- **Add confidence-threshold fallback gating**: when a component's minimum selection confidence drops below threshold, fall back to running all tests in that component (scoped).
- **Add confidence reporting**: confidence values emitted in `smart_run` output, dry-run, and `explain` output.

**Relations to Phase 1**: Confidence is computed from metadata already tracked (or soon tracked — `built_at`, `failed_item_count`, `total_discovered_items`). No new data collection is needed for the initial implementation.

## Impact

- Affected capabilities: `smart-selection` (MODIFIED `smart_run` decision logic), `coverage-index` (ADDED confidence metadata)
- New capabilities proposed: `confidence-scoring`
- Dependencies: `implement-coverage-layer`, `add-runtime-feedback` (for run history → confidence), `add-safety-invariants` (for fallback integration), `add-component-boundary` (for per-component confidence aggregation)
