# Index builder — builds and maintains the coverage index from per-item records.
#
# Provides the public API for single-item and bulk recording, index
# construction, and cache management.
#
# See REC-005 through REC-008 in
# openspec/changes/implement-coverage-layer/specs/recording/spec.md

module IndexBuilder

using SHA
using Serialization
import Dates: now

"""
    _record_single_item(test_file::AbstractString, item_name::AbstractString) -> Union{ItemCoverage, Nothing}

Record coverage for a single @testitem identified by its file and name.

Returns an `ItemCoverage` with the item's coverage data, or `nothing`
if the item is not found in the file.

This is a convenience API for single-item debugging. Called by
`Testimonial.record_item` in the parent module.

For bulk recording with caching and parallelism, use `record_all`.
"""
function _record_single_item(test_file::AbstractString, item_name::AbstractString)
    # Resolve the test file path
    abs_file = abspath(String(test_file))
    if !isfile(abs_file)
        throw(SystemError("test file not found: $(abs_file)"))
    end

    # Read the file and find the matching @testitem
    content = try
        read(abs_file, String)
    catch
        throw(SystemError("cannot read test file: $(abs_file)"))
    end

    # Use the parent module's helpers for discovery
    parent = Base.parentmodule(@__MODULE__)
    pattern = parent._TESTITEM_PATTERN
    tags = parent._parse_tags(content)
    fhash = bytes2hex(sha256(content))[1:12]

    # Find the matching @testitem
    found = false
    ref = nothing
    for m in eachmatch(pattern, content)
        name = m.captures[1]
        if name == item_name
            offset = m.offset
            line = count(==('\n'), content[1:offset]) + 1
            item_tags = get(tags, name, Symbol[])
            ref = parent.TestItemRef(abs_file, line, name, item_tags, fhash)
            found = true
            break
        end
    end

    if !found
        return nothing
    end

    # Record coverage using CoverageLayer
    return parent.record_item(ref)
end

# ── Helpers ───────────────────────────────────

"""
    _cache_key(ref::TestItemRef) -> String

Compute the per-item cache key for a test item.
The key is derived from the file hash and the item name, allowing
cache invalidation when the test file changes (new hash = new key).
"""
function _cache_key(ref)::String
    parent = Base.parentmodule(@__MODULE__)
    return "$(ref.file_hash)-$(ref.name)"
end

"""
    _cache_dir() -> String

Return the path to the per-item cache directory.
"""
function _cache_dir()::String
    return joinpath(".testimonial", "items")
end

"""
    _cache_path(ref) -> String

Return the full path to the cache file for a test item.
"""
function _cache_path(ref)::String
    return joinpath(_cache_dir(), "$(_cache_key(ref)).jls")
end

"""
    _git_hash() -> String

Get the current git HEAD hash. Returns "unknown" if not in a git repo
or if git fails.
"""
function _git_hash()::String
    try
        result = read(`git rev-parse HEAD`, String)
        return strip(result)
    catch
        return "unknown"
    end
end

"""
    _is_dirty() -> Bool

Check if the git workspace has uncommitted changes.
"""
function _is_dirty()::Bool
    try
        result = read(`git status --porcelain`, String)
        return !isempty(strip(result))
    catch
        return false
    end
end

"""
    _load_cached_record(ref) -> Union{ItemCoverage, Nothing}

Load a per-item cache record for the given ref. Returns `nothing` if
the cache file doesn't exist or can't be deserialized.
"""
function _load_cached_record(ref)
    path = _cache_path(ref)
    if !isfile(path)
        return nothing
    end
    try
        return open(deserialize, path, "r")
    catch
        return nothing
    end
end

"""
    _save_cached_record(ic)

Save a per-item cache record to disk.
Writes atomically via temp file + rename.
"""
function _save_cached_record(ic)
    path = _cache_path(ic.item)
    dir = dirname(path)
    mkpath(dir)
    tmppath = path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, ic)
    end
    mv(tmppath, path; force=true)
end

# ── record_all ────────────────────────────────

"""
    record_all(items, runner=SubprocessRunner(); incremental=true, force=false, test_dirs=["test/"]) -> CoverageIndex

Record coverage for all discovered @testitems and build a CoverageIndex.

Parallel recording via `Threads.@threads` — each item is recorded in its
own subprocess. The `runner` parameter allows injecting a mock runner
for testing (see REC-011).

## Keyword Arguments
- `incremental=true`: only re-record items whose test files have changed
  (identified by a change in `file_hash`). Cached records are used for
  unchanged items.
- `force=false`: if true, re-record all items regardless of cache state.
- `test_dirs`: directories to search for @testitem files (only used when
  `items` is empty and items are auto-discovered).

## Returns
A `CoverageIndex` containing the recorded coverage data for all items.

## Examples
```julia
# Full recording
index = record_all(discovered_items, SubprocessRunner(); force=true)

# Incremental — only re-record changed items
index = record_all(discovered_items, SubprocessRunner(); incremental=true)
```
"""
function record_all(
    items::Vector,
    runner=nothing;
    incremental::Bool=true,
    force::Bool=false,
    test_dirs::Vector{String}=String["test/"]
)::Any
    parent = Base.parentmodule(@__MODULE__)

    # Default runner is SubprocessRunner if none provided
    if runner === nothing
        runner = parent.SubprocessRunner()
    end

    isempty(items) && return parent.CoverageIndex(
        Dict{parent.TestItemRef, parent.ItemCoverage}(),
        _git_hash(),
        v"0.1.0",
        now()
    )

    # Check for dirty workspace
    dirty_suffix = _is_dirty() ? "-dirty" : ""

    # Determine which items need recording
    to_record = Set{Int}()
    cached_results = Dict{Int, Any}()

    for (i, ref) in enumerate(items)
        if force
            push!(to_record, i)
        elseif incremental
            # Check cache: if file_hash matches, use cached record
            cached = _load_cached_record(ref)
            if cached !== nothing && cached.item.file_hash == ref.file_hash
                cached_results[i] = cached
            else
                push!(to_record, i)
            end
        else
            push!(to_record, i)
        end
    end

    # Record needed items — parallel via Threads.@threads
    record_indices = collect(to_record)  # snapshot for thread safety
    fresh_results = Vector{Union{Any, Nothing}}(undef, length(items))
    fill!(fresh_results, nothing)

    if !isempty(record_indices)
        # Allocate a per-thread lock for results (no contention on Dict)
        Threads.@threads for idx in record_indices
            ref = items[idx]
            result = parent.record_item(runner, ref)
            fresh_results[idx] = result
            if result !== nothing
                # Cache the result
                _save_cached_record(result)
            end
        end
    end

    # Build the CoverageIndex
    item_map = Dict{parent.TestItemRef, parent.ItemCoverage}()

    for (i, ref) in enumerate(items)
        # Check fresh results first, then cached
        ic = nothing
        if fresh_results[i] !== nothing
            ic = fresh_results[i]
        elseif haskey(cached_results, i)
            ic = cached_results[i]
        end

        if ic !== nothing
            item_map[ref] = ic
        end
    end

    git_sha = _git_hash() * dirty_suffix
    return parent.CoverageIndex(item_map, git_sha, v"0.1.0", now())
end

export record_all

end # module IndexBuilder