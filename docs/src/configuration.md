# Configuration

Testimonial.jl reads configuration from `Testimonial.toml` in the project root.

## Example

```toml
[safety]
mode = "shadow"  # "shadow" (default) or "enforcing"

[confidence]
threshold = 0.7
stale_threshold_hours = 48

[components]
override = ["LibA", "LibB"]

[must_run]
# Force-select tests with specific tags when matching files change
"src/core/*.jl" = ["core_tests"]
"src/api/*.jl" = ["api_tests"]
```

## Sections

### `[safety]`

| Key | Default | Description |
|-----|---------|-------------|
| `mode` | `"shadow"` | Safety mode: `shadow` (compute + run all) or `enforcing` (only run selected) |

### `[confidence]`

| Key | Default | Description |
|-----|---------|-------------|
| `threshold` | `0.7` | Minimum confidence below which component falls back to full run |
| `stale_threshold_hours` | `48` | Hours before index is considered stale |

### `[components]`

| Key | Default | Description |
|-----|---------|-------------|
| `override` | `[]` | Explicit component list (for projects without Julia workspace) |

### `[must_run]`

Glob pattern → test tag mappings. When a changed file matches the glob,
all tests with the specified tag are force-selected.