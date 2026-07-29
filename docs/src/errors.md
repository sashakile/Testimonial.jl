---
title: Error Reference
description: Common errors, failure modes, and troubleshooting for Testimonial.jl
category: reference
---

# Error Reference

**TL;DR:** Common issues when using Testimonial, their causes, and how to fix them.

## Coverage Recording Errors

### Recording fails for an item

| Symptom | Cause | Fix |
|---------|-------|-----|
| `nothing` returned by `record_item` | Subprocess timed out or crashed | Check the test item runs in isolation: `julia --project -e 'include("test/foo.jl"); @testitem "..."'` |
| Inconsistent coverage data | Test modifies global state | Ensure `@testitem` does not depend on other tests running first |
| Slow recording | Large number of items | Use `record_batch` or `record_all(; batch_by_file=true)` to amortize startup cost |
| No coverage recorded | Test file not in `test/` directory | Specify custom `test_dirs` or move test file |
| No items discovered | Source files don't use `@testitem` macro | `@testitem` is required — bare `@test` or `@testset` blocks without `@testitem` are not discoverable |

### Batch recording failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Coverage attributed incorrectly | Batch recording over-approximates file-level union coverage | Use per-item recording (`record_all()`) for precise attribution |
| Batch subprocess fails | One item in the batch crashes | Identify the failing item and run it individually |

### Empty test pool

| Symptom | Cause | Fix |
|---------|-------|-----|
| `record_all` reports 0 items | No `@testitem` blocks found in `test/` | Check that your test files use the `@testitem` macro (not `@test` or `@testset` alone). Specify custom `test_dirs` if tests live elsewhere. |

## Index Errors

### Missing or corrupted index

| Symptom | Cause | Fix |
|---------|-------|-----|
| `load_index` returns `nothing` | No index file at `.testimonial/index.jls` | Run `record_all()` first |
| Index fails to load | Corrupted `.jls` file or schema version mismatch | Delete `.testimonial/` and re-run `record_all()` |
| Stale index warning | Index older than `stale_threshold_hours` (default: 24h) | Run `record_all()` to refresh |

### Index stale conditions

Testimonial considers an index stale and falls back to a full suite run when:

| Condition | Threshold |
|-----------|-----------|
| Index age | > `stale_threshold_hours` (configurable, default 24h) |
| Julia version changed | Any version mismatch |
| Git workspace is dirty | Uncommitted changes detected |

## Configuration Errors

| Symptom | Cause | Fix |
|---------|-------|-----|
| Settings ignored | Missing or unreadable `Testimonial.toml` | Create file at project root |
| Invalid `safety.mode` | Value not `"shadow"` or `"enforcing"` | Use one of the allowed values |
| Confidence override not applied | Component name doesn't match workspace | Check component names with `Testimonial.discover_components()` |
| Must-run rule doesn't trigger | Glob pattern doesn't match | Test the glob against the actual file path |

## Git Diff Errors

| Symptom | Cause | Fix |
|---------|-------|-----|
| No diff computed | No commits yet, or shallow clone | Ensure repository has history; use `--base-ref` to specify a ref |
| Empty change set | No files changed in the diff | Check that you have uncommitted changes or a valid ref range |
| Diff parsing fails | Unsupported diff format or binary files | Testimonial handles unified diff format; binary files are ignored and do not trigger test selection — consider must-run rules for binary-dependent tests |

## Runtime Errors

### Always-run set issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Tests always run despite passing | Test has not accumulated enough consecutive passes | Wait for eviction threshold (default 5 consecutive passes) |
| Test not in always-run set despite recent failure | Run history may be corrupted | Check `.testimonial/run_history.jls` and delete if corrupted |

### Incident management

| Symptom | Cause | Fix |
|---------|-------|-----|
| Incident not promoted | Fewer than 3 occurrences of the same failure | Wait for more occurrences or manually promote |
| False positive incidents | Quarantined tests not excluded | Ensure flaky detection is working; check quarantine metadata |
| Incidents lost | Index rebuild or `.testimonial/` deletion | Incidents are stored separately from the index at `.testimonial/incidents.jls` |

### Flaky detection

| Symptom | Cause | Fix |
|---------|-------|-----|
| Test randomly quarantined | Inconsistent outcomes across retries | Review the test for non-determinism |
| Flaky test not quarantined | Fewer than configured retries or consistent outcomes | Increase retry count or check test determinism |

## Protocol Adapter Errors

| Error | Meaning |
|-------|---------|
| `malformed JSON` | Input is not valid JSON |
| `missing 'command' field` | JSON object has no command key |
| `unknown command` | Unsupported protocol command |
| `missing 'params' field` | Command requires parameters |
| `'params.files' entries must be strings` | File list must be an array of strings |
| `file not found` | Referenced file doesn't exist |

## Troubleshooting Checklist

When something goes wrong:

1. **Check the index** — run `Testimonial.index_info()` to verify it exists and is recent
2. **Run in shadow mode** — `Testimonial.CLI.main(["--shadow"])` to see what would be selected
3. **Inspect incidents** — `Testimonial.CLI.main(["incidents"])` for missed-selection history
4. **Verify configuration** — Ensure `Testimonial.toml` is valid and in the project root
5. **Reset the index** — Delete `.testimonial/` and re-run `Testimonial.record_all()`
6. **Check the logs** — Look for error messages in the console output