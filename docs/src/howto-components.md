---
title: How to Configure Component Boundaries
description: Guide for setting up per-component test indices in Testimonial.jl for monorepo projects
category: how-to
---

# How to Configure Component Boundaries

**TL;DR:** Component boundaries let Testimonial isolate test selection per package in a Julia monorepo. Changes to one package only trigger tests in that package and its dependents — instead of running every test in the repo.

## Context & Prerequisites

This guide explains how to enable and configure component boundaries in Testimonial.jl. Before starting, ensure you have:

- A Julia **workspace monorepo** (Julia >= 1.12 with `[workspace]` or 1.11+ with `[sources]`)
- At least one `@testitem`-based test file per package
- A coverage index already recorded (run `Testimonial.record_all()` first)

## Step 1: Understand Auto-Detection

Testimonial automatically detects components from your workspace `Project.toml`. Each workspace member becomes a component:

```toml
# Project.toml (workspace root)
[workspace]
members = ["packages/LibA", "packages/LibB", "apps/AppC"]
```

This creates three components: `LibA`, `LibB`, and `AppC`. Test files in each package are assigned to that component.

## Step 2: Verify Component Detection

Check which components were discovered:

```bash
julia --project=. -e '
using Testimonial
components = Testimonial.discover_components()
println("Discovered components: ", components)
'
```

Expected output:
```
Discovered components: ["LibA", "LibB", "AppC"]
```

If your project doesn't use a workspace, see Step 3 for manual overrides.

## Step 3: Configure in Testimonial.toml (Optional)

```toml
[components]
# Only needed if auto-detection doesn't cover your project structure
override = ["LibA", "LibB", "AppC"]
```

The `override` key explicitly sets the component list. When `override` is empty (default), auto-detection from workspace `Project.toml` is used.

## Step 4: Re-Record Coverage with Components

After configuring components, re-record coverage to build per-component indices:

```bash
julia --project=. -e '
using Testimonial
Testimonial.record_all(; force=true, project_dir=pwd())
'
```

This creates:
```
.testimonial/
  index.jls          ← routing file (maps items → components)
  components/
    LibA/index.jls   ← per-component coverage index
    LibB/index.jls
    AppC/index.jls
  items/             ← cached per-item coverage records
```

## Step 5: Run with Component Resolution

Run smart selection as usual — component resolution happens automatically:

```bash
julia --project=. -e 'using Testimonial; Testimonial.CLI.run()'
```

If you change a file in `LibA`:
1. Testimonial detects the changed file belongs to `LibA`
2. Queries `LibA`'s index for affected tests
3. Checks inter-component dependencies: if `LibB` depends on `LibA`, also queries `LibB`
4. Returns aggregate selection across all affected components

## Step 6: Use Shard Output

For CI, component-aware sharding balances tests by estimated duration:

```bash
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--shards", "4"])'
```

This splits the selected tests into 4 roughly equal groups by total expected duration.

## Troubleshooting: Common Fail-States

| Symptom | Cause | Fix |
|---------|-------|-----|
| No components detected | No workspace `Project.toml` or empty `override` | Set `[components].override` in `Testimonial.toml` |
| Tests from wrong component selected | Incorrect component assignment for test file | Check `Testimonial.component_of(test_file)` — test files are assigned to the component matching their directory |
| Component override ignored | `override` is set but empty | Provide explicit component names |
| Index migration needed | Upgrading from flat to per-component mode | Run `Testimonial.migrate_index()` or delete `.testimonial/` and re-record from scratch |

## Further Exploration

- [Architecture → Component Resolution](architecture/) — Detailed explanation of the resolution algorithm
- [Configuration Reference → components](configuration/) — All component-related config keys
- [Error Reference](errors/) — Troubleshooting common issues