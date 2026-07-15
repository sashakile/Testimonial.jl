# Testimonial.jl — Contributor Toolchain

This document describes the development toolchain used in this project. All tools
are optional for casual contributors but **required** for PR authors.

## Quick Start

```bash
# Install all git hooks
lefthook install

# Run the full quality gate
just check
```

## Tools Overview

| Tool | Purpose | Config file |
|------|---------|-------------|
| **wai** | Reasoning, session handoffs, phase tracking | `.wai/` |
| **bd (beads)** | Issue tracking (tasks, bugs, epics) | `.beads/` |
| **openspec** | Capability specs & change proposals | `openspec/` |
| **pretender** | Code quality gates (complexity, duplication, mutation) | `pretender.toml` |
| **espectacular** | Spec-level validation (`ah check`) | `.espectacular/` |
| **testaruda** | Test selection engine (provenance-semiring analysis) | `testaruda.toml` |
| **lefthook** | Git hooks manager (pre-commit, pre-push, post-commit) | `lefthook.yml` |
| **just** | Command runner (task orchestration) | `justfile` |
| **GitHub Actions** | CI (tests, linting, nightly recording) | `.github/workflows/` |

## Installation

### Prerequisites

- **Julia** >= 1.11 (1.12 recommended)
- **just** — task runner (`brew install just` or `cargo install just`)
- **lefthook** — git hooks manager (`brew install lefthook` or `npm install -g lefthook`)

### Julia package setup

```bash
just install     # Instantiate Julia project deps
just test        # Run tests
```

### Tool installation

```bash
# wai (reasoning engine) — https://wai.orchestra.tools
# bd (beads) — https://github.com/charly-vibes/beads
# Already configured in this repo

# pretender — code quality
cargo install pretender
# or download from https://github.com/charly-vibes/pretender

# espectacular — spec-level validation
cargo install espectacular
# or download from https://github.com/charly-vibes/espectacular

# testaruda — test selection
cargo install testaruda
# or download from https://github.com/charly-vibes/testaruda

# openspec — specification management
# Install per https://github.com/charly-vibes/openspec

# lefthook — git hooks
npm install -g lefthook
# or: brew install lefthook
```

### Git hooks setup

```bash
lefthook install   # Installs pre-commit, pre-push, post-commit, post-merge hooks
```

## Workflow

### Daily development cycle

```bash
# 1. Start a session
just session-start

# 2. Find work
bd ready

# 3. Claim an issue
bd update <id> --claim

# 4. Write code (TDD: red → green → tidy)

# 5. Run quality gate before committing
just check

# 6. Commit (lefthook auto-runs pre-commit checks)
git add -p
git commit -m "feat: description"

# 7. Push (lefthook auto-runs pre-push checks)
git push

# 8. End session
just session-end
```

### Pre-commit hooks (lefthook)

Automatically run on `git commit`:

- **pretender check** — code quality thresholds
- **openspec validate** — spec consistency
- **espectacular check** — spec-level validation
- **Julia syntax check** — parse all staged `.jl` files
- **No debug prints** — reject `println`, `@show`, `@debug` in `src/`
- **No merge conflicts** — reject unresolved conflict markers

### Pre-push hooks

Automatically run on `git push`:

- **Julia tests** — `just test`
- **openspec validate** — full spec suite
- **pretender check** — quality gates
- **Beads integrity** — validate Dolt state

### CI (GitHub Actions)

Two workflows:

1. **CI** (`.github/workflows/ci.yml`) — runs on every PR and push to main:
   - Julia tests on 1.11 and 1.12
   - pretender code quality check
   - espectacular spec validation
   - openspec validation

2. **Nightly Recording** (`.github/workflows/nightly-record.yml`) — runs daily at 06:00 UTC:
   - Full coverage recording on main
   - Stores CoverageIndex as artifact

## Common Tasks

```bash
# List available commands
just

# Code quality
just lint           # pretender check
just complexity     # Show complexity hotspots
just duplication    # Show code duplication

# Spec management
just specs          # Validate specs
just specs-list     # List all capabilities
just changes        # List active change proposals

# Issue tracking
just bd-ready       # Find available work
just bd-list        # Show open issues
just bd-sync        # Push beads to remote

# Session management
just session-start  # Start a work session
just handoff        # Create session handoff
```

## Troubleshooting

### Lefthook hooks not running

```bash
lefthook check-install  # Check installation
lefthook uninstall      # Remove hooks
lefthook install -f     # Force reinstall
```

### pretender check fails

```bash
pretender doctor       # Diagnose config
pretender report       # View detailed report
pretender complexity   # Show complexity by function
```

### Beads/Dolt issues

```bash
bd dolt status         # Check Dolt state
bd dolt pull           # Pull from remote
bd dolt push           # Push to remote
```

### Testaruda issues

```bash
testaruda discover     # Update dependency graph
testaruda graph        # View dependency graph
testaruda select       # Select affected tests
```

## CI/CD Architecture

```
main branch                     PR branch
     │                               │
     ▼                               ▼
Nightly Recording              CI workflow
(06:00 UTC)                    (on push to PR)
     │                               │
     ├─ record_all()                  ├─ Julia tests (1.11, 1.12)
     ├─ upload index artifact         ├─ pretender check
     └─ cache index for PRs           ├─ espectacular check
                                      └─ openspec validate
                                           │
                                           ▼
                                      PR merge
                                           │
                                           ▼
                                      Main branch
                                      (triggers next nightly)
```

## References

- [wai workflow docs](.wai/AGENTS.md)
- [OpenSpec guide](openspec/AGENTS.md)
- [Beads workflow](.beads/README.md)
- [Project specification](openspec/project.md)