# Query engine — determines which @testitems are affected by changed files.
#
# Given a CoverageIndex and a list of changed files (from git diff or
# testaruda protocol), the query engine returns ImpactResults that identify
# which test items should be re-run and why.
#
# See SEL-002 through SEL-005 in
# openspec/changes/implement-coverage-layer/specs/smart-selection/spec.md

module Query

export query_files, coverage_gaps, nearest_covered_lines,
       query, direct_change_provider, unresolved_provider,
       must_run_provider, manual_edge_provider, runtime_edge_provider

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
function query_files(index, files::Vector{String}; component::Union{String,Nothing}=nothing)::Vector
    parent = _parent()
    isempty(files) && return parent.ImpactResult[]

    # Build a reverse index: file_path -> [TestItemRef, ...]
    file_to_items = Dict{String, Vector{parent.TestItemRef}}()
    for (ref, _) in index.items
        # Filter by component if specified
        if component !== nothing
            if ref.component == "" || ref.component != component
                continue
            end
        end
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
        elseif component === nothing
            # Only emit unresolved when not filtering by component
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

    # Aggregate coverage by file: file -> Set{covered_lines}
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
        if !haskey(file_coverage, file_path)
            continue
        end

        covered = file_coverage[file_path]
        sorted_changed = sort!(collect(changed_lines))
        i = 1
        while i <= length(sorted_changed)
            line = sorted_changed[i]
            if line in covered
                i += 1
                continue
            end

            gap_start = line
            gap_end = line

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
"""
function nearest_covered_lines(index, file::String, line::Int)
    parent = _parent()

    covered_lines = Set{Int}()
    for (ref, item_cov) in index.items
        if ref.file == file
            union!(covered_lines, item_cov.covered_lines)
        end
    end

    if isempty(covered_lines)
        return (nothing, nothing)
    end

    sorted_covered = sort!(collect(covered_lines))

    before = nothing
    for cl in reverse(sorted_covered)
        if cl <= line
            before = cl
            break
        end
    end

    after = nothing
    for cl in sorted_covered
        if cl >= line
            after = cl
            break
        end
    end

    return (before, after)
end

# ── Provider-based query engine ─────────────

"""
    query(providers, index, changed) -> Vector{ImpactResult}

Run a multi-provider query against the coverage index for changed files.

`providers` is a vector of provider functions. Each provider is called
as `provider(index, changed_files)` and returns `Vector{ImpactResult}`.

`changed` is a `Dict{String, Set{Int}}` mapping file paths to changed
line numbers (from `parse_unified_diff`).

Results are accumulated across all providers: if a test item receives
reasons from multiple providers, all reasons are collected. Items are
deduplicated by (file, name).

If no provider selected any items (all unresolved), the function returns
an empty vector -- the caller should fall back to running all tests.

# Examples
```julia
providers = [direct_change_provider, unresolved_provider]
results = query(providers, index, changed)
for r in results
    if r.selected
        println("Run \$(r.item.name): \$(r.reasons)")
    end
end
```
"""
function query(providers::Vector{<:Function}, index, changed::Dict{String, Set{Int}}; component::Union{String,Nothing}=nothing)::Vector
    parent = _parent()
    isempty(changed) && return parent.ImpactResult[]

    changed_files = collect(keys(changed))

    # Accumulate reasons per item across all providers
    # item_key (file => name) -> (ref, reasons, selected)
    item_map = Dict{Pair{String, String}, Tuple{Any, Vector{Any}, Bool}}()

    for provider in providers
        provider_results = provider(index, changed_files; component=component)
        for r in provider_results
            key = r.item.file => r.item.name
            if haskey(item_map, key)
                existing_ref, existing_reasons, existing_selected = item_map[key]
                append!(existing_reasons, r.reasons)
                item_map[key] = (existing_ref, existing_reasons, existing_selected || r.selected)
            else
                item_map[key] = (r.item, copy(r.reasons), r.selected)
            end
        end
    end

    results = parent.ImpactResult[]
    for (_, (ref, reasons, selected)) in item_map
        push!(results, parent.ImpactResult(ref, reasons, selected))
    end

    return results
end

"""
    direct_change_provider(index, changed_files) -> Vector{ImpactResult}

Provider: for files tracked in the CoverageIndex, returns `DirectChange`
reasons for all items in those files.

This is a provider function suitable for use with `query`.
"""
function direct_change_provider(index, changed_files::Vector{String}; component::Union{String,Nothing}=nothing)::Vector
    return query_files(index, changed_files; component=component)
end

"""
    unresolved_provider(index, changed_files) -> Vector{ImpactResult}

Provider: for files NOT tracked in the CoverageIndex, returns `Unresolved`
reasons. These are source files, config files, etc. that don't have
coverage data.

This is a provider function suitable for use with `query`.
"""
function unresolved_provider(index, changed_files::Vector{String}; component::Union{String,Nothing}=nothing)::Vector
    parent = _parent()

    # Build set of tracked files
    tracked_files = Set{String}()
    for (ref, _) in index.items
        push!(tracked_files, ref.file)
    end

    results = parent.ImpactResult[]
    seen = Set{Pair{String, String}}()

    for file in changed_files
        norm_file = isabspath(file) ? file : abspath(file)

        if norm_file in tracked_files
            continue
        end

        key = norm_file => ""
        if key in seen
            continue
        end
        push!(seen, key)

        ref = parent.TestItemRef(norm_file, 0, "")
        reason = parent.ImpactReason(parent.Unresolved, "file not tracked in coverage index: $(norm_file)")
        push!(results, parent.ImpactResult(ref, [reason], false, "unresolved file: $(norm_file)"))
    end

    return results
end

"""
    must_run_provider(index, changed_files; must_run_rules=MustRunRule[]) -> Vector{ImpactResult}

Provider: for files matching must-run rules, returns `AlwaysRun` reasons for
test items with matching tags. Only applies when one or more must_run_rules
are provided.

This is a provider function suitable for use with `query`.
"""
function must_run_provider(index, changed_files::Vector{String}; must_run_rules::Vector=parent.MustRunRule[], component::Union{String,Nothing}=nothing)
    parent = _parent()
    isempty(must_run_rules) && return parent.ImpactResult[]

    # Collect tags from matching rules
    matched_tags = Set{Symbol}()
    for rule in must_run_rules
        for file in changed_files
            if parent.matches_must_run_rule(rule, file)
                push!(matched_tags, rule.test_tag)
                break
            end
        end
    end

    isempty(matched_tags) && return parent.ImpactResult[]

    # Find all test items with matching tags
    results = parent.ImpactResult[]
    seen = Set{Pair{String, String}}()

    for (ref, _) in index.items
        if !isempty(intersect(ref.tags, matched_tags))
            key = ref.file => ref.name
            if key in seen
                continue
            end
            push!(seen, key)

            tag_str = join(string.(intersect(ref.tags, matched_tags)), ", ")
            reason = parent.ImpactReason(parent.AlwaysRun, "must-run rule matched (tag: $(tag_str))")
            push!(results, parent.ImpactResult(ref, [reason], true))
        end
    end

    return results
end

"""
    manual_edge_provider(index, changed_files) -> Vector{ImpactResult}

Provider: for files matching any manual edge's content_path, returns
`AlwaysRun` reasons for the associated test items.

Reads manual edges from the default storage path. Does not require
an index — manual edges operate on content paths regardless of coverage.

This is a provider function suitable for use with `query`.
"""
function manual_edge_provider(index, changed_files::Vector{String}; component::Union{String,Nothing}=nothing)::Vector
    parent = _parent()

    edges = parent.load_manual_edges()
    isempty(edges) && return parent.ImpactResult[]

    # Load quarantined tests to exclude
    quarantined = parent.get_quarantined_tests()

    results = parent.ImpactResult[]
    seen = Set{Pair{String, String}}()

    for edge in edges
        # Skip quarantined tests
        (edge.test.file, edge.test.name) in quarantined && continue

        # Check if any changed file matches this edge's content path
        # Uses suffix match: a changed file matches if its path ends with
        # the content path. This handles both absolute and relative paths
        # while avoiding false matches from suffix collisions.
        matched = any(f -> endswith(f, edge.content_path), changed_files)
        if !matched
            continue
        end

        # De-duplicate by test identity (file, name)
        key = edge.test.file => edge.test.name
        if key in seen
            continue
        end
        push!(seen, key)

        reason = parent.ImpactReason(parent.AlwaysRun, "manual edge: $(edge.content_path) -> $(edge.test.name)")
        push!(results, parent.ImpactResult(edge.test, [reason]))
    end

    return results
end

"""
    runtime_edge_provider(index, changed_files) -> Vector{ImpactResult}

Provider: for test items with runtime_edges, returns `AlwaysRun` reasons
when a changed file matches any runtime edge's source file.

Reads runtime edges from `index.runtime_edges`. For each test, if any of
its runtime edge source files are in the changed set, the test is forced
selected. This ensures that the feedback loop from runtime feedback
(FEED-002) feeds back into future selections.

This is a provider function suitable for use with `query`.
"""
function runtime_edge_provider(index, changed_files::Vector{String}; component::Union{String,Nothing}=nothing)::Vector
    parent = _parent()

    isempty(index.runtime_edges) && return parent.ImpactResult[]
    isempty(changed_files) && return parent.ImpactResult[]

    results = parent.ImpactResult[]
    seen = Set{Pair{String, String}}()

    for (ref, edges) in index.runtime_edges
        isempty(edges) && continue

        # Filter by component if specified
        if component !== nothing
            if ref.component == "" || ref.component != component
                continue
            end
        end

        # Check if any changed file matches any runtime edge source file
        matched = false
        matched_files = String[]
        for (src_file, _line) in edges
            if any(f -> endswith(f, src_file), changed_files)
                matched = true
                push!(matched_files, src_file)
            end
        end

        if !matched
            continue
        end

        key = ref.file => ref.name
        if key in seen
            continue
        end
        push!(seen, key)

        file_list = join(unique(matched_files), ", ")
        reason = parent.ImpactReason(parent.AlwaysRun, "runtime edge: $(file_list) changed -> $(ref.name)")
        push!(results, parent.ImpactResult(ref, [reason], true))
    end

    return results
end

end # module Query