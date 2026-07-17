# Standalone CLI entry points for Testimonial.jl.
#
# Provides the user-facing commands: record, run, explain, gaps, and
# index_info. All functions are lightweight wrappers around the core
# modules (IndexBuilder, Query, GitDiff, CoverageLayer).
#
# See design.md § 3.2 and tasks § 8 in
# openspec/changes/implement-coverage-layer/

module CLI

using Dates
import ..Testimonial: CoverageIndex, TestItemRef, ItemCoverage,
    discover_testitems, load_index, save_index, is_index_stale

export index_info, explain, run, SCHEMA_VERSION, STALE_INDEX_THRESHOLD_HOURS

# ── Constants ──────────────────────────────────

"""Current schema version for CoverageIndex. Bump on breaking changes."""
const SCHEMA_VERSION = 1

"""Default staleness threshold in hours. Beyond this, full suite runs."""
const STALE_INDEX_THRESHOLD_HOURS = 24

"""Test files that always trigger a full suite when changed."""
const ALWAYS_RUN_PREFIXES = ["test/runtests.jl", "test/runtests_quick.jl"]

"""Files whose modification triggers a full suite regardless of coverage."""
const SUITE_TRIGGER_FILES = ["Project.toml", "Manifest.toml"]

# ── index_info ─────────────────────────────────

"""
    index_info(; index_path::String=".testimonial/index.jls",
                 test_dirs::Vector{String}=String["test/"]) -> NamedTuple

Return metadata for the coverage index on disk.

Loads the persisted CoverageIndex and computes statistics. If no index
exists, returns a NamedTuple with `item_count=0`.

## Fields returned
- `git_sha` — commit SHA from the index
- `julia_version` — Julia version at index build time
- `built_at` — timestamp of index creation
- `schema_version` — schema version from the index
- `item_count` — number of successfully recorded items
- `file_count` — number of distinct source files with coverage
- `age_hours` — hours since index was built
- `total_discovered_items` — total @testitem blocks found
- `failed_item_count` — items that failed to record
- `index_present` — whether an index file exists on disk
"""
function index_info(; index_path::String=".testimonial/index.jls",
                      test_dirs::Vector{String}=String["test/"])::NamedTuple
    parent = Base.parentmodule(@__MODULE__)

    # Try to load the persisted index
    index = parent.load_index(index_path)

    if index === nothing
        discovered = parent.discover_testitems(test_dirs)
        return (
            git_sha = "",
            julia_version = string(VERSION),
            built_at = now(),
            schema_version = SCHEMA_VERSION,
            item_count = 0,
            file_count = 0,
            age_hours = 0.0,
            total_discovered_items = length(discovered),
            failed_item_count = length(discovered),
            index_present = false,
        )
    end

    # Compute statistics from the index
    item_count = length(index.items)
    files = Set{String}()
    for (_, ic) in index.items
        push!(files, ic.item.file)
    end
    file_count = length(files)

    discovered = parent.discover_testitems(test_dirs)
    total_discovered = length(discovered)
    failed = total_discovered - item_count
    age = (now() - index.created_at).value / (1000 * 3600)

    return (
        git_sha = index.git_hash,
        julia_version = hasfield(typeof(index), :julia_version) ? index.julia_version : string(VERSION),
        built_at = index.created_at,
        schema_version = SCHEMA_VERSION,
        item_count = item_count,
        file_count = file_count,
        age_hours = age,
        total_discovered_items = total_discovered,
        failed_item_count = failed,
        index_present = true,
    )
end

# ── explain ────────────────────────────────────

"""
    explain(test_file::AbstractString, item_name::AbstractString;
            index_path::String=".testimonial/index.jls") -> Vector{String}

Return a human-readable list of source files (with covered line counts)
for the given test item, as recorded in the coverage index.

Returns an empty vector if the item is not found or the index does not
exist.
"""
function explain(test_file::AbstractString, item_name::AbstractString;
                  index_path::String=".testimonial/index.jls")::Vector{String}
    parent = Base.parentmodule(@__MODULE__)

    index = parent.load_index(index_path)
    index === nothing && return String[]

    target = parent.TestItemRef(String(test_file), 0, String(item_name))

    for (ref, ic) in index.items
        if ref == target
            lines = String[]
            n_covered = length(ic.covered_lines)
            if n_covered > 0
                line_range = "$(first(ic.covered_lines))-$(last(ic.covered_lines))"
                push!(lines, "$(ref.file): lines $line_range (covered: $n_covered)")
            else
                push!(lines, "$(ref.file): no coverage data")
            end
            return lines
        end
    end

    return String[]
end

# ── run ────────────────────────────────────────

"""
    run(; base_ref::String="origin/main",
          index_path::String=".testimonial/index.jls",
          test_dirs::Vector{String}=String["test/"]) -> Union{Symbol, Vector}

Run the smart test selection pipeline.

Loads the coverage index, checks staleness, parses git diff against
`base_ref`, queries the index, and returns either:
- `:full_suite` — fallback signal (missing/stale index, Project.toml changes,
  coverage gaps, or always-run file changed)
- `Vector{TestItemRef}` — the selected items to run

# Pipeline
1. Load index — `:full_suite` if missing
2. Check staleness — `:full_suite` if stale
3. Get git diff — `:full_suite` if diff fails or is empty
4. Check for suite-trigger files (Project.toml, Manifest.toml)
5. Check for always-run prefixes (runtests.jl)
6. Query index for changed files
7. Check coverage gaps — `:full_suite` if gaps exist
8. Return selected items
"""
function run(; base_ref::String="origin/main",
               index_path::String=".testimonial/index.jls",
               test_dirs::Vector{String}=String["test/"])::Union{Symbol, Vector}
    parent = Base.parentmodule(@__MODULE__)

    # Step 1: Load index
    index = parent.load_index(index_path)
    if index === nothing
        @warn "No coverage index found at $index_path — running full suite"
        return :full_suite
    end

    # Step 2: Check staleness
    if parent.is_index_stale(index)
        @warn "Coverage index is stale — running full suite"
        return :full_suite
    end

    # Step 3: Get git diff
    diff_output = _get_git_diff(base_ref)
    if diff_output === nothing
        @warn "No git diff available — running full suite"
        return :full_suite
    end

    if isempty(strip(diff_output))
        return TestItemRef[]
    end

    # Step 4: Parse diff and check for trigger files
    repo_root = _git_repo_root()
    changed = parent.parse_unified_diff(diff_output, repo_root)
    changed_files = collect(keys(changed))

    for trigger in SUITE_TRIGGER_FILES
        if any(endswith(f, trigger) for f in changed_files)
            @warn "$trigger changed — running full suite"
            return :full_suite
        end
    end

    # Step 5: Check for always-run test files
    for prefix in ALWAYS_RUN_PREFIXES
        if any(contains(f, prefix) for f in changed_files)
            @warn "$prefix changed — running full suite"
            return :full_suite
        end
    end

    # Step 6: Query index for changed files in test directories
    selected = parent.query_files(index, changed_files)
    abs_test_dirs = [isabspath(d) ? d : abspath(d) for d in test_dirs]
    filtered = [
        item for item in selected
        if any(startswith(item.item.file, d) for d in abs_test_dirs)
    ]

    # Step 7: Check coverage gaps in changed source files
    source_files = [f for f in changed_files
                    if endswith(f, ".jl") && !any(startswith(f, d) for d in abs_test_dirs)]
    if !isempty(source_files)
        gaps = parent.coverage_gaps(index, source_files)
        if !isempty(gaps)
            @warn "Coverage gaps detected in source files — running full suite"
            return :full_suite
        end
    end

    return filtered
end

# ── Git helpers ────────────────────────────────

"""
    _get_git_diff(base_ref::String) -> Union{String, Nothing}

Run `git diff` against `base_ref` and return the diff text.
Returns `nothing` if git is not available or the ref doesn't exist.
"""
function _get_git_diff(base_ref::String)::Union{String, Nothing}
    try
        result = read(`git merge-base $(base_ref) HEAD`, String)
        if isempty(strip(result))
            return nothing
        end
        diff = read(`git diff $(strip(result))..HEAD --diff-filter=AM`, String)
        return diff
    catch
        return nothing
    end
end

"""
    _git_repo_root() -> String

Get the root directory of the current git repository.
Returns "." if not in a git repo.
"""
function _git_repo_root()::String
    try
        result = read(`git rev-parse --show-toplevel`, String)
        return strip(result)
    catch
        return "."
    end
end

end # module CLI