# Spike: Coverage Sidecar Attribution — Findings

## Summary

**Julia 1.12 does not generate `.jl.cov` sidecar files.** The coverage
mechanism was changed to use LCOV tracefiles (`--code-coverage=tracefile.info`).
This means the current `CoverageLayer.jl` implementation that relies on
`Coverage.jl`'s `process_file()` to parse `.jl.cov` files is **broken on
Julia 1.12**.

## Detailed Findings

### Old behavior (Julia ≤ 1.10)
- `julia --code-coverage=user myscript.jl` generates `.jl.cov` files next
  to each source file that was loaded
- `Coverage.process_file()` reads these `.jl.cov` files and maps execution
  counts back to source lines
- `.jl.cov` files are plain text with one execution count per line

### New behavior (Julia 1.12)
- `julia --code-coverage=tracefile.info` generates an LCOV-format tracefile
  instead of individual `.jl.cov` files
- The tracefile contains coverage data for all loaded files in a single file
- `--code-coverage=@<path>` tracks files under a specific directory
- `--code-coverage=@` (no path) tracks the current directory
- `--code-coverage=tracefile.info` supports format tokens for filename patterns

### What was tested
1. `--code-coverage=user` with `-e` expressions — no coverage generated
2. `--code-coverage=user` with `include()` of a file — no coverage generated
3. `--code-coverage=@.` with `using Package` — coverage generated in LCOV format
4. `--code-coverage=@.` with standalone script — no `.jl.cov` files generated
5. `--code-coverage=all` — same behavior as `user`
6. Symlinked shadow tree — symlinks are resolved by Julia, so coverage data
   appears under the real path, not the symlink path

### Impact on Testimonial.jl
- `CoverageLayer.jl`'s `parse_cov_sidecar()` function uses `Coverage.process_file()`
  which expects `.jl.cov` files
- `Coverage.jl` PackageCompat shows it supports Julia 1.6-1.11, not 1.12
- The `_collect_coverage()` function scans for `.jl.cov` files — this will find
  nothing on Julia 1.12
- **Both `record_item` and `SubprocessRunner` pathways are affected**

### Recommendation
The coverage layer needs to be updated for Julia 1.12's LCOV tracefile format:

1. **Short-term**: Use `Coverage.jl`'s `Coverage.process_folder()` or LCOV
   parsing functions if available in a compatible version
2. **Medium-term**: Implement a custom LCOV tracefile parser that reads
   `tracefile.info` and maps coverage data to source files
3. **Alternative**: Use `--code-coverage=@<path>` with a custom output format
   to generate per-file coverage data

### Success criteria
- ❌ Not met: Coverage sidecar attribution via `.jl.cov` files does not work
  on Julia 1.12
- ⚠ The symlinked shadow tree approach works in principle (Julia resolves
  symlinks to real paths), but the coverage data format has changed
- The fundamental concept (isolated subprocess → coverage trace → parse)
  is still valid, but the trace format is different

## Next Steps
1. Check if `Coverage.jl` has a version compatible with Julia 1.12
2. If not, implement a lightweight LCOV tracefile parser
3. Update `_collect_coverage()` to use the new parser
4. Update `parse_cov_sidecar()` to accept LCOV tracefile data