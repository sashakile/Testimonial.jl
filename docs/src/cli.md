# CLI Reference

## Usage

```bash
julia --project=. -e 'using Testimonial; Testimonial.CLI.main()'
```

## Flags

| Flag | Description |
|------|-------------|
| `--shadow` | Compute selection but run all tests (shadow mode) |
| `--enforcing` | Only run selected tests (enforcing mode) |
| `--base-ref <ref>` | Base git ref for diff (default: `origin/main`) |
| `--shards N` | Split selected tests into N balanced shards |

## Subcommands

### incidents

```bash
julia --project=. -e 'using Testimonial; Testimonial.CLI.main(["incidents"])'
```

List, dismiss, or promote missed-selection incidents.

## Module-level Functions

### `Testimonial.record_all()`
Record coverage for all test items in the project.

### `Testimonial.CLI.run(; shadow=false, base_ref="origin/main")`
Run smart selection on the current diff.

### `Testimonial.CLI.explain(test_file, item_name)`
Explain why a specific test was selected or excluded.

### `Testimonial.reconcile()`
Run full reconciliation — compare selection outcomes against full-run results.