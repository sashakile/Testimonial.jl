# Change: Add Provenance and Deep Explainability — Reason Chains, Exclusion Reasoning, and Persisted Provenance

> **Status (two-layer architecture): DEFERRED indefinitely.**
> Deep provenance chains are a debugging ergonomics feature, not a correctness
> requirement. Phase 1's basic `ImpactReason` types (`COVERED_LINE`,
> `TEST_FILE_CHANGED`) provide sufficient explainability for initial use.
> In adapter mode, testaruda's own provenance/reason-chain implementation
> covers this. Implement when standalone mode users request better debugging.

## Why

Testimonial.jl's current `explain` API returns "which files this test covers" — a flat list. When a developer asks "why wasn't my test selected?" or "why was it selected?" there's no chain of reasoning. This undermines trust in the tool, especially during onboarding. Provenance answers are the debugging interface.

## What Changes

- **Add reason chains**: for a selected test, return the chain of (changed file → lines → test) that caused selection, with each step annotated by analysis layer (coverage, inference, static, test-file-changed).
- **Add exclusion reasoning**: for a test that was NOT selected, explain why (e.g., "no changed file touches any covered line", "test has never been recorded", "test is in a different component with no dependency path").
- **Add persisted provenance**: store the provenance for each selection so it can be re-explained without re-running the query.
- **Add layered provenance view**: when multiple analysis layers contribute, show which layer(s) caused selection and how they interplay.

**Relations to Phase 1**: The `ImpactResult` and `ImpactReason` types already exist (CI-003). This change deepens them. The `explain` API already exists (SEL-006). Exclusion reasoning is additive.

## Impact

- Affected capabilities: `smart-selection` (MODIFIED `ImpactResult`, `explain` API), `coverage-index` (ADDED provenance persistence)
- New capabilities proposed: `provenance`
- Dependencies: `implement-coverage-layer` (needs working selection)