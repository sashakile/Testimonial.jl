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

export index_info, explain, SCHEMA_VERSION, STALE_INDEX_THRESHOLD_HOURS

# ── Constants ──────────────────────────────────

"""Current schema version for CoverageIndex. Bump on breaking changes."""
const SCHEMA_VERSION = 1

"""Default staleness threshold in hours. Beyond this, full suite runs."""
const STALE_INDEX_THRESHOLD_HOURS = 24

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
        # No index — return empty report
        # Still count how many items exist
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

    # Discover total items to compute failure count
    discovered = parent.discover_testitems(test_dirs)
    total_discovered = length(discovered)
    failed = total_discovered - item_count

    # Compute age
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

# Examples
```julia
explain("test/foo_test.jl", "test_foo")
# Returns: ["test/foo_test.jl: lines 1-3 (covered: 3)"]
```
"""
function explain(test_file::AbstractString, item_name::AbstractString;
                  index_path::String=".testimonial/index.jls")::Vector{String}
    parent = Base.parentmodule(@__MODULE__)

    # Load the index
    index = parent.load_index(index_path)
    index === nothing && return String[]

    # Build a TestItemRef for lookup (file_hash can be empty for matching)
    target = parent.TestItemRef(String(test_file), 0, String(item_name))

    # Find the item in the index
    for (ref, ic) in index.items
        if ref == target
            # Found it — build description strings
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

    # Not found
    return String[]
end

end # module CLI