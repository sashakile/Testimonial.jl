# Testimonial.jl

Test impact analysis for Julia monorepos. Given a set of code changes, selects
the minimal set of `@testitem`s required to validate those changes — turning a
30-minute CI suite into a 30-second feedback loop.

[![CI](https://github.com/sashakile/Testimonial.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/sashakile/Testimonial.jl/actions/workflows/ci.yml)
[![Docs](https://github.com/sashakile/Testimonial.jl/actions/workflows/docs.yml/badge.svg)](https://sashakile.github.io/Testimonial.jl)

## Features

| Feature | Description |
|---------|-------------|
| **Coverage Recording** | Per-item subprocess recording with parallel execution and cache |
| **Smart Selection** | Git diff → query → run only affected tests |
| **Confidence Scoring** | 4 signals with threshold-based fallback |
| **Provenance & Explainability** | Reason chains, exclusion reasoning, persisted provenance |
| **Safety Invariants** | Always-run set, shadow mode, incident detection, flaky quarantine |
| **Component Boundary** | Per-component indices, bottom-up resolution, shard planning |
| **Protocol Adapter** | JSON stdin/stdout for testaruda integration |
| **Runtime Feedback** | Post-run ingestion, edge learning, run history |

## Quick Start

```bash
# Install dependencies
just install

# Record coverage for all test items
julia --project -e 'using Testimonial; Testimonial.record_all()'

# Run smart selection (shadow mode by default)
julia --project=. -e 'using Testimonial; Testimonial.CLI.main()'

# See all commands
just --list
```

## CLI Reference

```bash
# Run smart selection (shadow mode by default)
julia --project=. -e 'using Testimonial; Testimonial.CLI.main()'

# Enforcing mode — only run selected tests
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--enforcing"])'

# Custom base ref for diff
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--base-ref", "origin/main"])'

# Shard output for CI
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--shards", "4"])'

# View index metadata and promotion readiness
julia --project=. -e 'using Testimonial; Testimonial.CLI.index_info()'

# List incidents
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["incidents"])'

# Dismiss an incident
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["incidents", "dismiss", "1"])'

# Explain why a test was selected or excluded
julia --project=. -e 'using Testimonial; for r in Testimonial.explain("test/foo.jl", "my test"); println(r); end'

# Explain with layered provenance view
julia --project=. -e 'using Testimonial; Testimonial.explain("test/foo.jl", "my test"; layers=true)'
```

### CLI Flags

| Flag | Effect |
|------|--------|
| `--shadow` | Shadow mode (compute selection, run all tests) |
| `--enforcing` | Enforcing mode (only run selected tests) |
| `--base-ref <ref>` | Git base ref for diff (default: `origin/main`) |
| `--shards <N>` | Number of CI shards (default: 0) |

## Configuration

Create a `Testimonial.toml` in your project root:

```toml
[safety]
mode = "shadow"         # "shadow" (default) or "enforcing"

[confidence]
threshold = 0.7          # Min confidence before fallback
stale_threshold_hours = 48

[components]
override = ["LibA", "LibB"]  # Explicit component list (optional)

[must_run]
# Force-select tests with specific tags when matching files change
"src/core/*.jl" = ["core_tests"]
"src/api/*.jl" = ["api_tests"]
```

## Safety Invariants

Testimonial includes a comprehensive safety architecture to prevent
silent CI gaps from missed selections.

### Shadow Mode

By default, Testimonial runs in **shadow mode**: it computes the smart
selection but still runs all tests. The selection is logged for inspection.
This is the safest default — you see what would be selected without
risking missed failures.

In **enforcing mode**, only the selected tests are run. Use this after
validating the selection is reliable.

### Incident Detection

When a full run reveals a test failure that the smart selection would have
skipped, Testimonial records a **candidate incident**:

```
$ testimonial incidents
Incidents (3):
  1: [Candidate] src/lib.jl → test_bar (2026-07-27 18:00)
  2: [Candidate] src/lib.jl → test_bar (2026-07-27 18:05)
  3: [Candidate] src/lib.jl → test_bar (2026-07-27 18:10)
```

Dismiss false positives:

```
$ testimonial incidents dismiss 1
Dismissed incident 1: src/lib.jl → test_bar [Candidate]
```

When the same failure is observed **3+ times** across independent changes,
the incident is promoted to a **manual edge** — a permanent rule forcing
selection.

### Always-Run Set

Tests that have recently failed are automatically included in every
selection, regardless of coverage analysis. Tests exit the always-run
set after 5 consecutive passing runs.

### Flaky Detection & Quarantine

Tests with inconsistent outcomes are automatically quarantined:
- Quarantined failures are excluded from incident detection
- Quarantined tests are skipped during coverage recording
- Tests re-enter the pool after `N` consecutive passes

## Data Files

| Path | Contents |
|------|----------|
| `.testimonial/index.jls` | Coverage index (or routing file in component mode) |
| `.testimonial/components/` | Per-component indices, fingerprints, and caches |
| `.testimonial/items/` | Per-item cached coverage records |
| `.testimonial/run_history.jls` | Test duration history for shard balancing |
| `.testimonial/incidents.jls` | Missed-selection incidents |
| `.testimonial/manual_edges.jls` | Promoted manual edges |
| `.testimonial/provenance/` | Persisted provenance records |
| `.testimonial/reconciliation/` | Timestamped reconciliation reports |
| `.testimonial/ingested_runs.jls` | Run keys for idempotent ingestion |

## Documentation

- [Full documentation](https://sashakile.github.io/Testimonial.jl) — API reference, CLI, architecture
- [Contributor guide](CONTRIBUTING.md) — toolchain setup, workflow, common tasks
- [Project specification](openspec/project.md) — domain model, architecture
- [Changelog](CHANGELOG.md) — release history

## License

MIT — see [LICENSE](LICENSE).