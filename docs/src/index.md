---
title: Testimonial.jl Documentation
description: Home page for Testimonial.jl documentation — test impact analysis for Julia monorepos
category: overview
---

# Testimonial.jl

**TL;DR:** Testimonial is a Julia-native test impact analysis engine. Given code changes (from a git diff), it selects the minimal set of `@testitem`s required to validate those changes — turning a 30-minute CI suite into a 30-second feedback loop on most PRs.

## Orientation

If you are new here, start here:

| Your goal | Go here |
|-----------|---------|
| Try it out | [Getting Started Tutorial](tutorial/) |
| Understand the CLI | [CLI Reference](cli/) |
| Configure your project | [Configuration Reference](configuration/) |
| Learn how it works | [Architecture](architecture/) |
| Troubleshoot issues | [Error Reference](errors/) |
| Contribute | [Contributor Guide](https://github.com/sashakile/Testimonial.jl/blob/main/CONTRIBUTING.md) |

## Quick Start

```julia
# Record coverage for all test items
using Testimonial
Testimonial.record_all()

# Run selection on the current diff
Testimonial.CLI.run()
```

## Feature Overview

- **Coverage Recording** — Per-item subprocess recording with parallel execution
- **Smart Selection** — Git diff → query → run only affected tests
- **Confidence Scoring** — 4 signals (freshness, quality, coverage, history) with threshold-based fallback
- **Provenance & Explainability** — Reason chains, exclusion reasoning, persistent provenance, layered views
- **Safety Invariants** — Always-run set, scoped fallback, flaky detection, shadow mode, incident recording
- **Component Boundary** — Per-component indices, bottom-up resolution, cached selection, shard planning
- **Protocol Adapter** — JSON stdin/stdout protocol for testaruda integration
- **Runtime Feedback** — Post-run ingestion, runtime edge learning, run history tracking