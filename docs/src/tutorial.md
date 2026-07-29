---
title: Getting Started Tutorial
description: Step-by-step tutorial for setting up and running Testimonial.jl on a Julia monorepo
category: tutorial
---

# Getting Started with Testimonial.jl

**TL;DR:** This tutorial walks through installing Testimonial, recording coverage, and running smart selection on a sample project. By the end you'll have a working test impact analysis setup.

## What You Will Learn

By completing this tutorial you will:
- Install Testimonial.jl and its dependencies
- Record coverage for all `@testitem`s in your project
- Run smart selection on a code change
- Interpret the selection results and understand why tests were chosen
- Use shadow mode to validate the selection before switching to enforcing mode

**Prerequisites:** Basic familiarity with Julia projects and `@testitem` syntax. No prior knowledge of test impact analysis is assumed.

## Prerequisites

Before starting, ensure you have:

- **Julia** >= 1.11 installed
- **just** command runner (`brew install just` or `cargo install just`)
- A **git repository** with Julia code and `@testitem`-based tests
- **ReTestItems.jl** in your project dependencies

> **No `just`?** Replace `just install` below with `julia --project -e 'import Pkg; Pkg.instantiate()'` — they are equivalent.

## Step 1: Install Testimonial

```bash
# Clone or navigate to your Julia project
cd my-julia-monorepo

# Install Testimonial and dependencies
just install
# Or: julia --project -e 'import Pkg; Pkg.instantiate()'
```

> **What happened:** `just install` runs `julia --project -e 'import Pkg; Pkg.instantiate()'` which installs all project dependencies including Testimonial if it's in your `Project.toml`.

## Step 2: Record Coverage

Record coverage for all `@testitem`s in the `test/` directory:

```bash
julia --project -e 'using Testimonial; Testimonial.record_all()'
```

**Expected output:** (no output on success, or warnings for items that fail to record)

> **What happened:** Testimonial discovered all `@testitem` blocks, ran each in an isolated subprocess with `--code-coverage=user`, parsed the output, and built a `CoverageIndex` at `.testimonial/index.jls`. This index maps source lines to test items for fast queries.

### Verify the index

```bash
julia --project -e 'using Testimonial; println(Testimonial.index_info())'
```

This shows metadata: how many items were recorded, when the index was built, and the Julia version used.

## Step 3: Make a Code Change

Edit a source file — for example, change a function implementation in `src/lib.jl`:

```julia
# Before
function add(a, b)
    return a + b
end

# After
function add(a, b)
    return a + b + 0  # intentionally unnecessary change
end
```

Save the file. The change is now in your working tree.

## Step 4: Run Smart Selection (Shadow Mode)

Run Testimonial in shadow mode to see what tests *would* be selected:

```bash
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--shadow"])'
```

**Expected output:** A summary of the selection:
- Which files changed
- How many tests were selected
- Which always-run tests were added
- Any incidents detected

In shadow mode, **all tests still run** — the selection is logged for inspection only.

## Step 5: Interpret the Results

Review the selection output:

- **Selected tests** — These were chosen because they cover the changed lines in `src/lib.jl`. The reason chain shows: `changed file:lib.jl → covered by test:test_lib.jl`.
- **Always-run tests** — Tests that recently failed or have no history are automatically included.
- **Unresolved files** — If a changed file has no coverage in the index, it's marked as unresolved and the full suite runs as a fallback.

To see detailed selection reasons for a specific test:

```bash
julia --project=. -e 'using Testimonial; for r in Testimonial.explain("test/lib.jl", "test_add"); println(r); end'
```

## Step 6: Switch to Enforcing Mode

Once you've verified the selection is reliable in shadow mode, switch to enforcing mode:

```bash
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["--enforcing"])'
```

In enforcing mode, **only the selected tests run**. This is where the time savings come from — a 30-minute suite becomes a 30-second one.

> **Warning:** Always validate in shadow mode before switching to enforcing. If the selection misses a test that would have caught a bug, that bug will be missed in enforcement.

## Step 7: Check for Incidents

After a full run (shadow or enforcing), check for missed-selection incidents:

```bash
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["incidents"])'
```

If an incident is detected (a test failed that the selection would have skipped), it's recorded as a `Candidate`. After 3 total occurrences of the same failure (`promote_threshold=3`), it's automatically promoted to a permanent selection rule.

The first occurrence creates a `Candidate`, the second adds another occurrence, and the third promotes it to a permanent manual edge.

## Recap & Next Steps

You've successfully:
1. ✅ Installed Testimonial and recorded coverage
2. ✅ Made a code change and ran smart selection
3. ✅ Interpreted the selection output
4. ✅ Verified in shadow mode before switching to enforcing

Next, explore:
- **[Configuration Reference](configuration/)** — Customize thresholds, must-run rules, and component boundaries
- **[Architecture](architecture/)** — Understand how the system works in depth
- **[Error Reference](errors/)** — Troubleshoot common issues
- **[CLI Reference](cli/)** — All available commands and flags

### Advanced: Large Monorepos

If your project has 10+ packages and 1000+ test items:

- **Enable component boundaries** — Testimonial auto-detects workspace components and creates per-component indices. This allows changes in one package to only trigger tests in that package and its dependents. See [Architecture → Component Resolution](architecture/).
- **Use batch recording** — `record_all(; batch_by_file=true)` amortizes Julia's ~144ms subprocess startup cost by running all items in a test file together. Use for initial/incremental recording; switch to per-item for precise attribution.
- **Configure shards** — `--shards N` splits selected tests into balanced groups for CI parallelism. See [CLI Reference → Flags](cli/).
- **Set must-run rules** — Force-select critical test packages when specific files change. See [Configuration → must_run](configuration/).