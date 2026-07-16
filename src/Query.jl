# Query engine — determines which @testitems are affected by changed files.
#
# Given a CoverageIndex and a list of changed files (from git diff or
# testaruda protocol), the query engine returns ImpactResults that identify
# which test items should be re-run and why.
#
# See SEL-002 through SEL-005 in
# openspec/changes/implement-coverage-layer/specs/smart-selection/spec.md

module Query

export query_files, coverage_gaps, nearest_covered_lines

# ── Helpers ───────────────────────────────────

"""Get the parent module (Testimonial) for type access."""
_parent() = Base.parentmodule(@__MODULE__)

# ── query_files ──────────────────────────────

"""
    query_files(index, files) -> Vector{ImpactResult}

Given a CoverageIndex and a list of changed file paths, return ImpactResults
for all test items that are affected by the changes.

For each file:
- If the file is a test file tracked in the index, all items in that file
  get a `DirectChange` reason and `selected = true`.
- If the file is not tracked in the index (source file, config file, etc.),
  the result is `Unresolved` — meaning the system cannot determine which
  tests to run and should fall back to running all tests.

Results are deduplicated: if multiple changed files affect the same test
item, the item appears once with all reasons accumulated.
"""
function query_files(index, files::Vector{String})::Vector
    parent = _parent()
    isempty(files) && return parent.ImpactResult[]

    # Build a reverse index: file_path → [TestItemRef, ...]
    file_to_items = Dict{String, Vector{parent.TestItemRef}}()
    for (ref, _) in index.items
        f = ref.file
        if !haskey(file_to_items, f)
            file_to_items[f] = parent.TestItemRef[]
        end
        push!(file_to_items[f], ref)
    end

    seen = Set{Pair{String, String}}()
    results = parent.ImpactResult[]

    for file in files
        norm_file = isabspath(file) ? file : abspath(file)

        if haskey(file_to_items, norm_file)
            for ref in file_to_items[norm_file]
                key = ref.file => ref.name
                if key in seen
                    continue
                end
                push!(seen, key)

                reason = parent.ImpactReason(parent.DirectChange, "file changed: $(norm_file)")
                push!(results, parent.ImpactResult(ref, [reason], true))
            end
        else
            ref = parent.TestItemRef(norm_file, 0, "")
            reason = parent.ImpactReason(parent.Unresolved, "file not tracked in coverage index: $(norm_file)")
            push!(results, parent.ImpactResult(ref, [reason], false))
        end
    end

    return results
end

# ── coverage_gaps ────────────────────────────

"""
    coverage_gaps(index, changed) -> Vector{CoverageGap}

Find coverage gaps (contiguous uncovered regions) in changed files.

`changed` is a `Dict{String, Set{Int}}` mapping file paths to the set
of changed line numbers (from `parse_unified_diff`).

For each changed file that is tracked in the `CoverageIndex`, computes
which lines are covered (aggregated across all test items in that file)
and which are not. Contiguous regions of uncovered lines within the
changed regions are returned as `CoverageGap`s.

Files not tracked in the index are excluded from the result.
"""
function coverage_gaps(index, changed::Dict{String, Set{Int}})::Vector
    parent = _parent()
    isempty(changed) && return parent.CoverageGap[]

    # Aggregate coverage by file: file → Set{covered_lines}
    file_coverage = Dict{String, Set{Int}}()
    for (ref, item_cov) in index.items
        f = ref.file
        if !haskey(file_coverage, f)
            file_coverage[f] = Set{Int}()
        end
        union!(file_coverage[f], item_cov.covered_lines)
    end

    gaps = parent.CoverageGap[]

    for (file_path, changed_lines) in changed
        # Only process files that have coverage data
        if !haskey(file_coverage, file_path)
            continue
        end

        covered = file_coverage[file_path]

        # Find gaps: contiguous regions of changed lines that are NOT covered
        sorted_changed = sort!(collect(changed_lines))
        i = 1
        while i <= length(sorted_changed)
            line = sorted_changed[i]
            if line in covered
                i += 1
                continue
            end

            # Start of a gap
            gap_start = line
            gap_end = line

            # Extend the gap while consecutive lines are uncovered
            j = i + 1
            while j <= length(sorted_changed)
                next_line = sorted_changed[j]
                if next_line == gap_end + 1 && !(next_line in covered)
                    gap_end = next_line
                    j += 1
                else
                    break
                end
            end

            push!(gaps, parent.CoverageGap(file_path, gap_start, gap_end))
            i = j
        end
    end

    return gaps
end

# ── nearest_covered_lines ────────────────────

"""
    nearest_covered_lines(index, file::String, line::Int) -> Tuple{Union{Int, Nothing}, Union{Int, Nothing}}

Find the nearest covered line before and after a given line in a file.

Returns a tuple `(before, after)` where:
- `before` is the nearest covered line number at or before `line`,
  or `nothing` if no covered line exists before or at `line`.
- `after` is the nearest covered line number at or after `line`,
  or `nothing` if no covered line exists after or at `line`.

Coverage is aggregated across all test items in the index for the file.
"""
function nearest_covered_lines(index, file::String, line::Int)
    parent = _parent()

    # Aggregate covered lines for this file across all items
    covered_lines = Set{Int}()
    for (ref, item_cov) in index.items
        if ref.file == file
            union!(covered_lines, item_cov.covered_lines)
        end
    end

    if isempty(covered_lines)
        return (nothing, nothing)
    end

    # Find the file's total line count for bounds checking
    total_lines = typemax(Int)
    try
        content = read(file, String)
        total_lines = count(==('\n'), content)
    catch
        # Use the max covered line as a bound
        total_lines = maximum(covered_lines)
    end

    sorted_covered = sort!(collect(covered_lines))

    # Find nearest covered line at or before `line`
    before = nothing
    for cl in reverse(sorted_covered)
        if cl <= line
            before = cl
            break
        end
    end

    # Find nearest covered line at or after `line`
    after = nothing
    for cl in sorted_covered
        if cl >= line
            after = cl
            break
        end
    end

    return (before, after)
end

end # module Query