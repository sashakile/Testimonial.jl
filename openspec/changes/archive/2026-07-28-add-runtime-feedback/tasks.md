## 1. Post-run ingestion pipeline
- [x] 1.1 Add `ingest(; run_key::String)` function that parses coverage sidecars from the last run
- [x] 1.2 Add `ingest` call to `smart_run` after `runtests` exits, guarded by a config flag (`auto_ingest`, default: true)
- [x] 1.3 Implement edge dedup: skip recording if (test_item, content_unit) pair already exists

## 2. Runtime edge creation
- [x] 2.1 Add `runtime_edges` field to `CoverageIndex` (parallel to `inference_edges`, `static_edges`)
- [x] 2.2 Modify `query` to include runtime edges in the lookup path
- [x] 2.3 On ingestion, compute diff between pre-run and post-run coverage; add new edges

## 3. Run history persistence
- [x] 3.1 Define `RunHistoryEntry` struct (outcomes, duration, attempt_count, failure_rate, first_seen, last_seen)
- [x] 3.2 Implement `.testimonial/run_history.jls` read/write with atomic rename
- [x] 3.3 Expose `Testimonial.history(test_ref)` for querying per-test history

## 4. Idempotent ingestion
- [x] 4.1 Track ingested run keys in `.testimonial/ingested_runs.jls`
- [x] 4.2 Check run key before any write; skip if duplicate
- [x] 4.3 Prune old run keys (> N days, configurable)

## 5. External input recording
- [x] 5.1 Allow `@testitem "name" external_inputs=["config/app.toml"]` syntax
- [x] 5.2 Store external inputs in `CoverageIndex` alongside coverage edges
- [x] 5.3 Include external input files in diff parsing and selection query