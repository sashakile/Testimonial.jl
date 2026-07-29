---
title: Configuration Reference
description: Complete reference for Testimonial.toml — safety, confidence, components, and must-run rules
category: reference
---

# Configuration Reference

**TL;DR:** Testimonial reads settings from `Testimonial.toml` in the project root. This file is optional — all keys have sensible defaults.

## File Location

`Testimonial.toml` must be placed in the project root (where your `Project.toml` lives). If the file is missing, all defaults are used.

## Example

```toml
[safety]
mode = "shadow"  # "shadow" (default) or "enforcing"

[confidence]
threshold = 0.7
stale_threshold_hours = 48

[confidence.components]
PkgA = 0.5
PkgB = 0.8

[components]
override = ["LibA", "LibB"]

[must_run]
# Force-select tests with specific tags when matching files change
"src/core/*.jl" = ["core_tests"]
"src/api/*.jl" = ["api_tests"]
```

## Sections

### `[safety]`

Controls how Testimonial handles uncertainty and safety guarantees.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mode` | string | `"shadow"` | Safety mode: `"shadow"` (compute selection + run all tests) or `"enforcing"` (only run selected tests) |

### `[confidence]`

Controls the confidence scoring system that gates fallback behavior.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `threshold` | float | `0.7` | Minimum confidence score below which a component falls back to full suite run. Clamped to `[0, 1]`. |
| `stale_threshold_hours` | integer | `48` | Hours before the index freshness signal decays. Affects confidence scoring — older indices get lower freshness scores. **This is distinct from the hardcoded index staleness check (24h) in the CLI**, which always triggers a full suite run regardless of confidence. |

### `[confidence.components]`

Per-component confidence threshold overrides. Key is component name, value is threshold.

```toml
[confidence.components]
PkgA = 0.5   # lower threshold for PkgA (less critical)
PkgB = 0.9   # higher threshold for PkgB (critical component)
```

### `[components]`

Controls component boundary behavior for monorepos.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `override` | array of strings | `[]` | Explicit component list for projects without a Julia workspace. Components are auto-detected from workspace `Project.toml` when this is empty. |

### `[must_run]`

Glob pattern → test tag mappings. When a changed file matches a glob, all tests with the specified tag are force-selected.

```toml
[must_run]
"src/core/*.jl" = ["core_tests"]
"src/api/*.jl" = ["api_tests"]
"src/database/*.jl" = ["db_tests", "migration_tests"]
```

## Error States

### Missing or invalid `Testimonial.toml`

| Symptom | Cause | Fix |
|---------|-------|-----|
| Testimonial uses all defaults | No `Testimonial.toml` found | Create file, or rely on defaults |
| Testimonial ignores settings | File is invalid TOML | Validate with a TOML parser (e.g., `toml-test`) |
| Component override ignored | `override` is empty or components not found | Verify component names match workspace `Project.toml` |

> **Note:** Index staleness (always triggers full suite) uses a separate hardcoded threshold of 24h in the CLI. The `[confidence].stale_threshold_hours` only affects the freshness component of the confidence score — it does not control whether the index is considered too stale to use.

### Confidence threshold misconfiguration

| Symptom | Cause | Fix |
|---------|-------|-----|
| All tests always run full suite | Threshold set too high (e.g., `1.0`) | Lower threshold or ensure index is fresh |
| Selected tests miss failures | Threshold set too low | Raise threshold or run in shadow mode to validate selection |
| Per-component override not applied | Component name mismatch | Check component name spelling; use `Testimonial.components_below_threshold()` to debug |

### Must-run rule failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Rule not applying | Glob pattern doesn't match changed files | Test glob pattern against actual file paths |
| Too many tests selected | Glob is too broad | Narrow the pattern or use more specific tags |
| Tests not force-selected | Tag name mismatch | Verify the tag used in `@testitem` matches the rule