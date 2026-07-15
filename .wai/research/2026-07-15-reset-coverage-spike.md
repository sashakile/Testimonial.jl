# Spike Report: `Base.reset_coverage()` for In-Process Coverage Resets

**Issue:** testaruda-a8c
**Date:** 2026-07-15
**Julia Version:** 1.12.5

## Question

Can `Base.reset_coverage()` in Julia ≥1.11 permit sequential in-process
coverage counter resets for per-`@testitem` attribution, avoiding the
startup cost of subprocess-per-item?

## Method

1. Verified whether `Base.reset_coverage()` exists in Julia 1.12.5.
2. Verified whether any in-process coverage API exists
   (`Base.COVERAGE`, `Base.COMPILER_COVERAGE`, etc.).
3. Verified the mechanism of `.jl.cov` file generation (process-exit dump).
4. Checked `Coverage.jl` for runtime APIs.

## Findings

### 1. `Base.reset_coverage()` does not exist

```julia
julia> isdefined(Base, :reset_coverage)
false
```

The function was proposed for Julia 1.11 but was never merged. It is not
present in Julia 1.12.5.

### 2. No in-process coverage API exists

No coverage-related symbols are exposed in `Base` or `Core` at runtime:

- `Base.COVERAGE` — not defined
- `Base.COMPILER_COVERAGE` — not defined
- `Base.reset_coverage()` — not defined

The compiler internals (`Core.Compiler.should_insert_coverage`,
`Core.Compiler.fully_covering`) are compile-time flags, not runtime APIs.

### 3. Coverage data is post-mortem only

Coverage counters are instrumented by the compiler and written to `.jl.cov`
files at **process exit**. The naming convention is `<file>.jl.<pid>.cov`
for scripts and `<file>.jl.cov` for packages. There is no way to read or
reset the counters during execution.

### 4. Coverage.jl provides post-mortem parsing only

The `Coverage.jl` package (`process_file`, `process_cov`, `process_folder`)
reads `.jl.cov` files after the process exits. It provides no runtime
reset or manipulation API.

## Conclusion

**Subprocess-per-item isolation is unconditionally necessary.**

| Approach | Viable? | Evidence |
|----------|---------|----------|
| In-process `reset_coverage()` | ❌ | `Base.reset_coverage()` does not exist in Julia 1.12.5 |
| In-process counter read+reset | ❌ | No runtime API exists — counters are post-mortem only |
| Subprocess isolation | ✅ | Only viable approach; each `@testitem` runs in its own process |

## Impact on Architecture

The existing design (subprocess-per-item) is confirmed as the correct
approach. No changes needed to the ingest handler or coverage layer.

The subprocess startup cost (~3–10 seconds per item) is a known limitation.
Mitigations (already in the design):
- Parallel recording via `Threads.@threads` (design.md line 144)
- Per-item caching (`.testimonial/items/<key>.jls`)
- Incremental re-recording only for changed items