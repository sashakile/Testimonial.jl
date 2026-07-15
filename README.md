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

## Documentation

- [Contributor guide](CONTRIBUTING.md) — toolchain setup, workflow, common tasks
- [Project specification](openspec/project.md) — domain model, architecture

## License

MIT — see [LICENSE](LICENSE).