# Testimonial.jl

Test impact analysis for Julia monorepos. Given a set of code changes, selects
the minimal set of `@testitem`s required to validate those changes — turning a
30-minute CI suite into a 30-second feedback loop.

## Quick Start

```julia
# Record coverage for all test items
using Testimonial
Testimonial.record_all()

# Run selection on the current diff
Testimonial.CLI.run()
```

## Features

- **Coverage Recording** — Per-item subprocess recording with parallel execution
- **Smart Selection** — Git diff → query → run only affected tests
- **Confidence Scoring** — 4 signals (freshness, quality, coverage, history) with threshold-based fallback
- **Provenance & Explainability** — Reason chains, exclusion reasoning, persistent provenance, layered views
- **Safety Invariants** — Always-run set, scoped fallback, flaky detection, shadow mode, incident recording
- **Component Boundary** — Per-component indices, bottom-up resolution, cached selection, shard planning
- **Protocol Adapter** — JSON stdin/stdout protocol for testaruda integration
- **Runtime Feedback** — Post-run ingestion, runtime edge learning, run history tracking