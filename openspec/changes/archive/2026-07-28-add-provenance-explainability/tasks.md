## 1. Reason chains
- [x] 1.1 Define `ProvenanceLink` struct (layer, content_unit, detail, next)
- [x] 1.2 Add `chain::Vector{ProvenanceLink}` to `ImpactReason`
- [x] 1.3 Build reason chain during `query`: trace from changed line through analysis layers to test
- [x] 1.4 Display reason chain in dry-run output

## 2. Exclusion reasoning
- [x] 2.1 Implement `explain(test_ref; exclude=true)` that computes exclusion reason from index + diff
- [x] 2.2 Handle cases: not-in-index, no-coverage-overlap, different-component, changed-lines-mismatch
- [x] 2.3 Display exclusion reason as human-readable string with actionable suggestions

## 3. Persisted provenance
- [x] 3.1 Store provenance after each `smart_run` at `.testimonial/provenance/<run_key>.jls`
- [x] 3.2 Load persisted provenance on `explain` calls when run key matches
- [x] 3.3 Implement sliding-window pruning (keep last N runs, configurable)

## 4. Layered view in explain
- [x] 4.1 Group reasons by `LayerKind` in display output
- [x] 4.2 Show intersection/union semantics: "selected by coverage AND static" vs "selected by coverage OR static"
- [x] 4.3 Add `--layers` flag to `explain` CLI