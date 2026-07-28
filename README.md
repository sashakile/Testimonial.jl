# Testimonial.jl

Test impact analysis for Julia monorepos. Given a set of code changes, selects
the minimal set of `@testitem`s required to validate those changes — turning a
30-minute CI suite into a 30-second feedback loop.

## Status

This project is in **MVP development** (research/design phase). See
[CONTRIBUTING.md](CONTRIBUTING.md) for the contributor toolchain.

## Quick Start

```bash
# Install dependencies
just install

# Run tests
just test

# See all commands
just --list
```

## Safety Invariants

Testimonial includes a set of safety mechanisms to detect and correct
selection mistakes — tests that the selection algorithm would skip but
that would have caught a failure.

### Shadow Mode

By default, Testimonial runs in **shadow mode**: it computes the smart
selection but still runs all tests (`:full_suite`). The selection is
logged for inspection. This is the safest default — you see what would
be selected without risking missed failures.

```toml
# Testimonial.toml — switch to enforcing mode
[safety]
mode = "enforcing"
```

In **enforcing mode**, only the selected tests are run. Use this when
you've validated that the selection is reliable.

Pass `--shadow` or `--enforcing` on the CLI to override the config.

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

### Incident Promotion

When the same failure is observed **3+ times** across independent changes,
the incident is **promoted** from `Candidate` to `Promoted`. This creates
a **manual edge** — a permanent rule that forces the test to be selected
whenever the implicated content changes:

```
Promoted → ManualEdge("src/lib.jl" → "test_bar")
```

Manual edges are stored in `.testimonial/manual_edges.jls` and are
automatically applied during selection. View promotion readiness:

```julia
julia> index_info()
(candidate_count = 1, promoted_count = 3, manual_edge_count = 1, ...)
```

### Reconciliation Pipeline

The `reconcile()` function orchestrates the full post-run pipeline:

1. **Detect** missed selection incidents via `compare_selection_vs_outcomes`
2. **Save** new incidents
3. **Promote** qualifying incidents (threshold-based)
4. **Create** manual edges from promoted incidents
5. **Persist** a timestamped report to `.testimonial/reconciliation/`

Reports include incident counts, promotion stats, and quarantine exclusions.

### Flaky Test Detection

Tests with inconsistent outcomes (pass/fail across runs) can be
automatically **quarantined**:

- Quarantined test failures are **excluded from incident detection**
- Quarantined manual edges are **excluded from selection**
- Tests re-enter the pool after `N` consecutive passes
- `record_all(; skip_quarantined=true)` skips quarantined tests during
  coverage recording

### Data Files

| Path | Contents |
|------|----------|
| `.testimonial/incidents.jls` | Serialized `MissedSelectionIncident` vector |
| `.testimonial/manual_edges.jls` | Serialized `ManualEdge` vector |
| `.testimonial/reconciliation/` | Timestamped reconciliation reports |
| `.testimonial/index.jls` | Coverage index |
| `.testimonial/components/` | Per-component fingerprints and caches |
| `.testimonial/run_history.jls` | Test duration history for shard balancing |

## Documentation

- [Contributor guide](CONTRIBUTING.md) — toolchain setup, workflow, common tasks
- [Project specification](openspec/project.md) — domain model, architecture

## License

MIT — see [LICENSE](LICENSE).