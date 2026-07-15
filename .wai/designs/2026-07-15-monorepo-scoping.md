# Design Decision: Monorepo Scoping for Discover Command

**Issue:** testaruda-1x5
**Date:** 2026-07-15
**Context:** `implement-coverage-layer` Phase 1 (single-package support)

## Problem

Julia monorepos contain multiple packages, each with their own `Project.toml`
and `test/` directory. When the adapter's `discover` command is invoked, how
should it discover `@testitem`s across packages?

## Options

### Option 1: Single-pass discover (whole repo tree)

The adapter walks the entire repo, finds every `Project.toml`, resolves the
workspace layout, and merges all `@testitem`s into a flat set.

**Pros:**
- Simple for the user: one `testaruda select` call covers the entire repo
- testaruda sees the full picture for cross-package impact analysis

**Cons:**
- Must resolve workspace `[sources]` and `[workspace]` declarations
- Different packages may have different test runner configurations
- Flat node IDs lose package context (hard to route `run-args` per package)
- Single `ReTestItems.runtests` invocation across package boundaries
  may not work — each package has its own project environment
- testaruda's `testaruda.toml` is per-directory; a single adapter process
  cannot easily map to multiple package configurations

### Option 2: Per-package invocation (recommended)

The adapter is designed for a single package. The user (or CI script) invokes
`testaruda select` once per package. Each invocation spawns a separate adapter
instance rooted at the package directory.

**Pros:**
- Natural isolation: each package has its own `Project.toml`, test runner
  configuration, and workspace
- Aligns with testaruda's single-store architecture — each invocation
  manages one package's dependency graph
- Simpler adapter code: no workspace resolution, no cross-package routing
- Users already run tests per-package in CI (matrix jobs); this maps
  naturally to the existing workflow
- Each `ReTestItems.runtests` invocation runs within the correct package
  project environment

**Cons:**
- User must configure testaruda per package (or use a wrapper script)
- No cross-package edge detection in Phase 1 (acceptable — Phase 1 is
  single-package only)

## Recommendation

**Adopt Option 2 (per-package invocation).** Rationale:

1. **Phase 1 scope:** The explicit scope is single-package support. There is
   no need to solve the multi-package problem now.
2. **Architectural alignment:** testaruda's `testaruda.toml` is per-directory,
   and the adapter protocol is stateless per invocation. A single adapter
   process cannot know about other packages without a workspace-wide
   configuration file — which is the `add-component-boundary` Phase 2 work.
3. **Forward compatibility:** When Phase 2 adds component architecture,
   it can add a workspace-level adapter that orchestrates per-package
   invocations internally, or a new `discover --workspace` flag. The
   per-package adapter remains unchanged.
4. **CI pattern:** Julia monorepo CI typically runs `julia --project=pkg test/`
   per package. The per-package adapter maps exactly to this pattern.

## Implementation

The adapter's `discover` command will:

1. Look for `Project.toml` in the **current working directory**.
2. If found, parse it to determine the package name and test directory.
3. Call `ASTParser.discover_testitems` with the single package's test dir.
4. Return `@testitem` nodes with node IDs prefixed by `package_name:test_file:item_name`.

The `testaruda.toml` for a monorepo looks like:

```toml
[adapters]
".jl" = "julia --project=PkgA bin/testaruda_adapter.jl"
```

And CI invokes per package:

```bash
cd PkgA && testaruda select --changed-files <ref-range>
cd PkgB && testaruda select --changed-files <ref-range>
```

## Future Enhancement (Phase 2)

When `add-component-boundary` is implemented, a workspace-level adapter
could be added that:

1. Reads the workspace `[sources]` from the root `Project.toml`.
2. Spawns per-package adapter instances via subprocess.
3. Merges results and adds cross-package dependency edges.
4. Reports the combined set to testaruda.

This is fully backward-compatible with the per-package adapter design.