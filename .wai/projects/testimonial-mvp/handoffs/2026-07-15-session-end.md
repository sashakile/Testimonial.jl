---
date: 2026-07-15
project: testimonial-mvp
phase: research
---

# Session Handoff

## What Was Done

<!-- Summary of completed work -->

## Key Decisions

<!-- Decisions made and rationale -->

## Gotchas & Surprises

<!-- What behaved unexpectedly? Non-obvious requirements? Hidden dependencies? -->

## What Took Longer Than Expected

<!-- Steps that needed multiple attempts. Commands that failed before the right one. -->

## Open Questions

<!-- Unresolved questions -->

## Next Steps

<!-- Prioritized list of what to do next -->

## Context

### open_issues

```
○ testimonial-9se ● P0 [epic] Implement Coverage Layer (MVP)
├── ○ testimonial-0ap ● P0 Compute file_hash for each test file
├── ○ testimonial-0iq ● P0 Implement discover_testitems using AST walk
├── ○ testimonial-0q2 ● P0 Implement atomic write in Persistence.jl
├── ○ testimonial-0r5 ● P0 Create src/Testimonial.jl with module skeleton
├── ○ testimonial-0zr ● P0 Implement record_all with parallel recording
├── ○ testimonial-18p ● P0 Implement subprocess command construction
├── ○ testimonial-1bz ● P0 Implement record_item for single-item debugging
├── ○ testimonial-2df ● P0 Implement query with deduplication and reason accumulation
├── ○ testimonial-2k2 ● P0 Create driver.jl in scripts/TestimonialRunner/
├── ○ testimonial-3dk ● P0 Create test/runtests.jl and verify just test passes
├── ○ testimonial-3pc ● P0 Write unit test for record_item with MockRunner
├── ○ testimonial-7pe ● P0 Implement test-file-changed detection
├── ○ testimonial-8um ● P0 Implement build_index from per-item records
├── ○ testimonial-99u ● P0 Write integration test for building CoverageIndex
├── ○ testimonial-9yu ● P0 Implement .jl.cov sidecar parsing
├── ○ testimonial-ach ● P0 Handle new, deleted, and renamed files in diff parser
├── ○ testimonial-adh ● P0 Spike: Validate coverage sidecar attribution
├── ○ testimonial-amd ● P0 Implement query_files
├── ○ testimonial-bl6 ● P0 Implement timeout handling for subprocesses
├── ○ testimonial-bt2 ● P0 Create scripts/TestimonialRunner/Project.toml
├── ○ testimonial-cn4 ● P0 Implement cache cleanup in IndexBuilder.jl
├── ○ testimonial-cti ● P0 Implement parse_unified_diff returning Dict{String, Set{Int}}
├── ○ testimonial-dx3 ● P0 Write unit tests for struct equality, hash, round-trip persistence
├── ○ testimonial-e47 ● P0 Implement record_item for SubprocessRunner
├── ○ testimonial-efd ● P0 Write unit tests against sample diff strings
├── ○ testimonial-ekf ● P0 Implement coverage_gaps with nearest_covered_lines
├── ○ testimonial-ey0 ● P0 Resolve relative diff paths to absolute form
├── ○ testimonial-fgr ● P0 Write unit tests for query engine
├── ○ testimonial-g1o ● P0 Implement per-item cache read/write
├── ○ testimonial-gpo ● P0 Implement schema and Julia version checks on load
├── ○ testimonial-i29 ● P0 Implement index_info function in Inspector.jl
├── ○ testimonial-kbh ● P0 Create public API surface with re-exports
├── ○ testimonial-lqy ● P0 Implement explain function in Inspector.jl
├── ○ testimonial-mar ● P0 Create Project.toml with package metadata and deps
├── ○ testimonial-mc0 ● P0 Implement smart_run with index load, git diff, query
├── ○ testimonial-nue ● P0 Define enums and structs in src/Types.jl
├── ○ testimonial-oe2 ● P0 Spike: Benchmark subprocess overhead for 1000+ items
├── ○ testimonial-oja ● P0 Implement == and hash for TestItemRef
├── ○ testimonial-sip ● P0 Extract tags declarations from @testitem blocks
├── ○ testimonial-uvk ● P0 Define AbstractRunner and SubprocessRunner
├── ○ testimonial-v3z ● P0 Implement save_index, load_index, save_item_record, load_item_record
├── ○ testimonial-vm5 ● P0 Write unit tests with synthetic test files
├── ○ testimonial-wah ● P0 Write integration test for recording a @testitem
└── ○ testimonial-we3 ● P0 Write tests for explain and index_info
○ testimonial-023 ● P1 Add MODIFIED recording delta to add-component-boundary
○ testimonial-18k ● P1 Rename add-runtime-feedback spec folder to runtime-feedback
○ testimonial-275 ● P1 Add MODIFIED smart-selection delta to add-safety-invariants
○ testimonial-2ep ● P1 Add MODIFIED coverage-index delta to add-component-boundary
○ testimonial-2qv ● P1 Add layer_data field to CoverageIndex struct

--------------------------------------------------------------------------------
Total: 50 issues (50 open, 0 in progress)

Status: ○ open  ◐ in_progress  ● blocked  ✓ closed  ❄ deferred
```

