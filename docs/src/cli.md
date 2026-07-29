---
title: CLI Reference
description: Complete reference for Testimonial.jl command-line interface — flags, subcommands, exit codes, and environment variables
category: reference
---

# CLI Reference

**TL;DR:** Testimonial provides a standalone CLI via `Testimonial.CLI.main()` for running smart selection, recording coverage, explaining selections, and managing incidents.

## Usage

```bash
# Run smart selection (shadow mode by default)
julia --project=. -e 'using Testimonial; Testimonial.CLI.main()'

# Explicit mode selection
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--enforcing"])'

# Custom base ref
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--base-ref", "origin/main"])'

# Shard output for CI
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--shards", "4"])'
```

## Flags

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--shadow` | — | active when no mode specified | Compute selection but run all tests. Logs selection for inspection. Safest default. |
| `--enforcing` | — | — | Only run the selected tests. Use after validating the selection is reliable. |
| `--base-ref` | git ref | `origin/main` | Git base reference for computing the diff. |
| `--shards` | integer N | 0 (no sharding) | Split selected tests into N balanced shards. Outputs per-shard test lists. |

> **Note:** `--shadow` and `--enforcing` are mutually exclusive. If neither is specified, the mode from `Testimonial.toml` is used (default: `shadow`).

## Subcommands

### `record`

Record coverage for all test items and build the coverage index. Run this once to initialize the index, then periodically (e.g., nightly in CI) to refresh it.

```bash
julia --project=. -e 'using Testimonial; Testimonial.record_all()'
```

```bash
# Force re-record all items (ignore cache)
julia --project=. -e 'using Testimonial; Testimonial.record_all(force=true)'

# Incremental recording (default: only re-record changed items)
julia --project=. -e 'using Testimonial; Testimonial.record_all(incremental=true)'
```

### `run`

Run smart selection and execute the selected tests. Fails gracefully if no index exists (falls back to full suite with an informational message).

```bash
# Default (shadow mode)
julia --project=. -e 'using Testimonial; Testimonial.CLI.run()'

# Enforcing mode
julia --project=. -e 'using Testimonial; Testimonial.CLI.run(shadow=false)'

# Custom base ref
julia --project=. -e 'using Testimonial; Testimonial.CLI.run(base_ref="origin/main")'
```

### `explain`

Show why a test was selected or excluded from the selection.

```bash
# Basic explanation
julia --project=. -e 'using Testimonial; for r in Testimonial.explain("test/foo.jl", "my test"); println(r); end'

# Layered provenance view
julia --project=. -e 'using Testimonial; Testimonial.explain("test/foo.jl", "my test"; layers=true)'
```

### `gaps`

Report changed lines that have no recorded coverage.

```bash
julia --project=. -e 'using Testimonial; Testimonial.CLI.gaps()'
```

### `incidents`

Manage missed-selection incidents.

```bash
# List all incidents
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["incidents"])'

# Dismiss an incident
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["incidents", "dismiss", "1"])'
```

### `index_info`

View metadata about the coverage index.

```bash
julia --project=. -e 'using Testimonial; println(Testimonial.index_info())'
```

## Exit Codes

The CLI returns 0 on success and non-zero on failure. Specific exit codes are not currently differentiated — check stderr output for error details.

| Code | Meaning |
|------|---------|
| 0 | Success — all selected tests passed |
| 1 | Failure — one or more tests failed or an error occurred |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TESTIMONIAL_ITEMS` | Used by the batch recording driver to specify which items to record in a single subprocess. |

## Example Workflows

### Development loop

```bash
# 1. Record coverage (first time or after adding tests)
julia --project=. -e 'using Testimonial; Testimonial.record_all()'

# 2. Make code changes
vim src/lib.jl

# 3. Run smart selection (shadow mode)
julia --project=. -e 'using Testimonial; Testimonial.CLI.main()'

# 4. Review the selection log — are the right tests selected?

# 5. When confident, switch to enforcing mode
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--enforcing"])'
```

### CI pipeline

```bash
# Nightly: full coverage recording
julia --project=. -e 'using Testimonial; Testimonial.record_all(); Testimonial.CLI.index_info()'

# PR check: smart selection with sharding
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--shards", "4"])'
```