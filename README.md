# Testimonial.jl

Test impact analysis for Julia monorepos.

[![CI](https://github.com/sashakile/Testimonial.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/sashakile/Testimonial.jl/actions/workflows/ci.yml)
[![Docs](https://github.com/sashakile/Testimonial.jl/actions/workflows/docs.yml/badge.svg)](https://sashakile.github.io/Testimonial.jl)

**TL;DR:** Given a set of code changes, Testimonial selects the minimal set of `@testitem`s required to validate those changes — turning a 30-minute CI suite into a 30-second feedback loop.

## Quick Start

```bash
# Install the package
just install

# Record coverage for all test items
julia --project -e 'using Testimonial; Testimonial.record_all()'

# Run smart selection on the current diff (shadow mode by default)
julia --project=. -e 'using Testimonial; Testimonial.CLI.main()'

# See all available commands
just --list
```

## Features

| Feature | Description |
|---------|-------------|
| **Coverage Recording** | Per-item subprocess recording with parallel execution and cache |
| **Smart Selection** | Git diff → query → run only affected tests |
| **Inference Layer** | `@snoopi_deep` capture for newly added methods not yet in coverage |
| **Static Analysis** | JET-based entrypoint and abstract dispatch analysis |
| **[Confidence Scoring](https://sashakile.github.io/Testimonial.jl/configuration/)** | 4 signals with threshold-based fallback |
| **[Provenance & Explainability](https://sashakile.github.io/Testimonial.jl/architecture/)** | Reason chains, exclusion reasoning, persisted provenance |
| **[Safety Invariants](https://sashakile.github.io/Testimonial.jl/architecture/)** | Always-run set, shadow mode, incident detection, flaky quarantine |
| **[Component Boundary](https://sashakile.github.io/Testimonial.jl/architecture/)** | Per-component indices, bottom-up resolution, shard planning |
| **[Protocol Adapter](https://sashakile.github.io/Testimonial.jl/architecture/)** | JSON stdin/stdout for testaruda integration |
| **[Runtime Feedback](https://sashakile.github.io/Testimonial.jl/configuration/)** | Post-run ingestion, edge learning, run history |

## Documentation

| Resource | Description |
|----------|-------------|
| [Full documentation site](https://sashakile.github.io/Testimonial.jl) | API reference, CLI, architecture |
| [Getting Started](https://sashakile.github.io/Testimonial.jl/tutorial/) | Step-by-step walkthrough |
| [CLI Reference](https://sashakile.github.io/Testimonial.jl/cli/) | Command-line flags, subcommands, exit codes |
| [Configuration](https://sashakile.github.io/Testimonial.jl/configuration/) | Testimonial.toml reference |
| [Architecture](https://sashakile.github.io/Testimonial.jl/architecture/) | Design decisions, data flow, pipelines |
| [Error Reference](https://sashakile.github.io/Testimonial.jl/errors/) | Common errors and troubleshooting |
| [Contributor Guide](CONTRIBUTING.md) | Toolchain setup, workflow, common tasks |
| [Changelog](CHANGELOG.md) | Release history |

## Requirements

- Julia >= 1.11 (1.12 recommended for workspace monorepo support)
- `ReTestItems.jl` for test item discovery and execution

## License

MIT — see [LICENSE](LICENSE).