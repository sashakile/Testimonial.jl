# Spike: Subprocess Overhead Benchmark — Findings

## Summary

**❌ Not met:** Subprocess overhead is ~144ms per Julia instance. For 1000 items:
- Sequential: 144s (72× over the 2s threshold)
- Max parallel (16 cores): ~9s (4.5× over threshold)

## Results

| Configuration | Per subprocess | 1000 sequential | 1000 parallel-16 |
|---|---|---|---|
| Empty `julia -e` | 144ms | 144s | 9s |
| With driver.jl load | ~144ms (similar) | 144s | 9s |

## Analysis

The overhead is dominated by Julia's process startup time (~130-160ms per
invocation). This is a fundamental platform limitation:
- Julia's JIT compilation at startup
- OS process creation overhead
- Library loading (even for an empty `-e` expression)

The subprocess overhead cannot be eliminated — it's inherent to the
architecture of recording each @testitem in an isolated subprocess.

## Mitigations

1. **Parallelism (`Threads.@threads`)**: Already implemented in `record_all`.
   On a 16-core CI runner, 1000 items at 144ms/item ÷ 16 threads = ~9s.
   This is still above the 2s threshold.

2. **Incremental caching**: Already implemented. Only re-records items
   whose test files changed. For a typical PR touching 1-5 test files,
   only 1-5 subprocesses are needed (~0.7s).

3. **Batching**: If subprocess overhead is still a concern, batch multiple
   @testitems into a single subprocess invocation. The driver.jl could
   accept a list of item names instead of a single one.

4. **Acceptance**: For most CI scenarios, the incremental mode means
   only a small number of items are re-recorded per commit. The full
   `record_all` (1000+ items) is a rare event (initial build, cache
   invalidation).

## Recommendation

The current architecture is acceptable for real-world usage because:
- Incremental mode handles the common case (few changed items)
- Full re-record is rare (cache invalidation, initial setup)
- The 144ms baseline is a Julia platform limit, not an implementation issue

If faster full re-record is needed, implement batching (multiple
@testitems per subprocess) or use a long-running Julia process that
accepts recording commands via stdin (like the protocol adapter does).

## Environment
- Julia 1.12.5
- 16 CPU cores available
- Julia started with 1 thread (benchmark default)
- For CI: typically 2-4 threads available on GitHub Actions runners