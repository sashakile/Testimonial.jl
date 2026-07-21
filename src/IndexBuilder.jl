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
    record_all(items, runner=SubprocessRunner(); incremental=true, force=false, test_dirs=["test/"], project_dir=nothing) -> CoverageIndex

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
- `project_dir=nothing`: if provided, per-component CoverageIndex files
  are saved under `.testimonial/components/<name>/index.jls` and a
  routing file is written at `.testimonial/index.jls`.

## Returns
A `CoverageIndex` containing the recorded coverage data for all items.

## Examples
```julia
# Full recording
index = record_all(discovered_items, SubprocessRunner(); force=true)

# Incremental — only re-record changed items
index = record_all(discovered_items, SubprocessRunner(); incremental=true)

# Per-component recording
index = record_all(discovered_items, SubprocessRunner(); force=true, project_dir=pwd())
```
"""
function record_all(
    items::Vector,
    runner=nothing;
    incremental::Bool=true,
    force::Bool=false,
    test_dirs::Vector{String}=String["test/"],
    project_dir::Union{String,Nothing}=nothing
)::Any
    parent = Base.parentmodule(@__MODULE__)

    # Default runner is SubprocessRunner if none provided
    if runner === nothing
        runner = parent.SubprocessRunner()
    end

    isempty(items) && return parent.CoverageIndex(
        Dict{parent.TestItemRef, parent.ItemCoverage}(),
        _git_hash(),
        string(VERSION),
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

    # Save per-component indices if project_dir is provided
    if project_dir !== nothing
        _save_per_component_indices(parent, item_map, String(project_dir), git_sha)
    end

    return parent.CoverageIndex(item_map, git_sha, string(VERSION), v"0.1.0", now())
end

# ── Per-component index persistence ────────────

"""
    _save_per_component_indices(parent, item_map, project_dir, git_sha)

Build and save per-component CoverageIndex objects from a flat item map.

Groups items by their owning component (using component_paths and
component_of), creates a CoverageIndex per component, and writes each
to `.testimonial/components/<name>/index.jls`. Also saves the routing
file at `.testimonial/index.jls`.

Items that don't belong to any known component are saved under a
"__unmapped__" component.
"""
function _save_per_component_indices(
    parent::Module,
    item_map::Dict,
    project_dir::String,
    git_sha::String
)::Nothing
    # Discover components and their workspace paths
    path_map = parent.component_paths(project_dir)

    # If no components discovered, nothing to save
    isempty(path_map) && return nothing

    # Group items by component
    comp_groups = Dict{String, Vector{Pair{Any, Any}}}()
    for (ref, ic) in item_map
        # Determine component for this item
        comp = if ref.component != ""
            ref.component
        else
            result = parent.component_of(ref.file, path_map)
            result === nothing ? "__unmapped__" : string(result)
        end

        if !haskey(comp_groups, comp)
            comp_groups[comp] = Pair{Any, Any}[]
        end
        push!(comp_groups[comp], ref => ic)
    end

    # Build and save per-component indices
    for (comp_name, pairs) in comp_groups
        comp_map = Dict{typeof(first(pairs).first), typeof(first(pairs).second)}()
        for (ref, ic) in pairs
            comp_map[ref] = ic
        end

        comp_index = parent.CoverageIndex(comp_map, git_sha, string(VERSION), v"0.1.0", now())
        comp_path = parent.component_index_path(comp_name)
        save_index(comp_index, comp_path)
    end

    # Save routing file with all component names (excluding unmapped)
    component_names = [Symbol(k) for k in keys(comp_groups) if k != "__unmapped__"]
    save_routing(".testimonial", component_names)

    return nothing
end

export record_all, build_index

# ── build_index ───────────────────────────────

"""
    build_index(items_dir::AbstractString) -> CoverageIndex

Build a CoverageIndex from per-item cache records in the given directory.

Scans `items_dir` for `.jls` files, deserializes each into an `ItemCoverage`,
and constructs a `CoverageIndex`. Non-`.jls` files are ignored.

This is a recovery/rebuild utility — it reconstructs the index from cached
per-item records without re-recording anything.

## Returns
A `CoverageIndex` containing all successfully deserialized records.
"""
function build_index(items_dir::AbstractString)::Any
    parent = Base.parentmodule(@__MODULE__)

    if !isdir(items_dir)
        return parent.CoverageIndex(
            Dict{parent.TestItemRef, parent.ItemCoverage}(),
            _git_hash(),
            string(VERSION),
            v"0.1.0",
            now()
        )
    end

    item_map = Dict{parent.TestItemRef, parent.ItemCoverage}()

    for entry in readdir(items_dir)
        path = joinpath(String(items_dir), entry)
        if !isfile(path) || !endswith(entry, ".jls")
            continue
        end

        ic = try
            open(deserialize, path, "r")
        catch
            nothing
        end

        if ic !== nothing && ic isa parent.ItemCoverage
            item_map[ic.item] = ic
        end
    end

    return parent.CoverageIndex(item_map, _git_hash(), string(VERSION), v"0.1.0", now())
end

# ── Index persistence ──────────────────────────

"""
    save_index(index::CoverageIndex, path::AbstractString)

Persist a CoverageIndex to disk via serialization.

Creates parent directories if needed and writes atomically via
temp-file + rename.
"""
function save_index(index, path::AbstractString)::Nothing
    dir = dirname(String(path))
    mkpath(dir)
    tmppath = String(path) * ".tmp"
    open(tmppath, "w") do io
        serialize(io, index)
    end
    mv(tmppath, String(path); force=true)
    return nothing
end

"""
    load_index(path::AbstractString) -> Union{CoverageIndex, Nothing}

Load a persisted CoverageIndex from disk.

Returns `nothing` if the file doesn't exist, can't be read, or fails
deserialization.
"""
function load_index(path::AbstractString)
    p = String(path)
    if !isfile(p)
        return nothing
    end
    try
        result = open(deserialize, p, "r")
        parent = Base.parentmodule(@__MODULE__)
        if result isa parent.CoverageIndex
            return result
        end
        return nothing
    catch
        return nothing
    end
end

"""
    is_index_stale(index::CoverageIndex; stale_threshold_hours::Int=24) -> Bool

Check whether a CoverageIndex is stale and should be rebuilt.

Returns `true` if:
- The index is older than `stale_threshold_hours` (default: 24h)
- The Julia version has changed since the index was built
- The git workspace is dirty

Used by the CLI for fallback decisions — a stale index triggers a full
suite run instead of a selective run.
"""
function is_index_stale(index; stale_threshold_hours::Int=24)::Bool
    parent = Base.parentmodule(@__MODULE__)

    # Check Julia version mismatch
    if hasfield(parent.CoverageIndex, :julia_version)
        if index.julia_version != string(VERSION)
            return true
        end
    end

    # Check age threshold
    age_hours = (now() - index.created_at).value / (1000 * 3600)
    if age_hours > stale_threshold_hours
        return true
    end

    # Check dirty workspace
    if _is_dirty()
        return true
    end

    return false
end

# Re-export for CLI convenience
export save_index, load_index, is_index_stale, clean_cache

"""
    clean_cache(; test_dirs::Vector{String}=String["test/"],
                  items_dir::AbstractString=joinpath(".testimonial", "items")) -> Int

Remove orphaned cache records from the items directory.

Orphaned records are `.jls` files whose `TestItemRef` no longer matches
any discovered @testitem. This can happen when:
- A test file is deleted
- A @testitem block is removed or renamed
- A test file's content changes (new file_hash)

Returns the number of orphaned records removed.
"""
function clean_cache(; test_dirs::Vector{String}=String["test/"],
                       items_dir::AbstractString=joinpath(".testimonial", "items"))::Int
    parent = Base.parentmodule(@__MODULE__)
    dir = String(items_dir)
    isdir(dir) || return 0

    # Discover current @testitems
    current = parent.discover_testitems(test_dirs)
    current_keys = Set{String}()
    for ref in current
        push!(current_keys, _cache_key(ref))
    end

    # Scan cache directory for orphaned files
    removed = 0
    for entry in readdir(dir)
        path = joinpath(dir, entry)
        if !isfile(path) || !endswith(entry, ".jls")
            continue
        end

        # Try to load the record to get its key
        ic = try
            open(deserialize, path, "r")
        catch
            nothing
        end

        if ic === nothing || !(ic isa parent.ItemCoverage)
            # Corrupted or invalid — remove it
            rm(path; force=true)
            removed += 1
            continue
        end

        # Check if this item's key is still current
        key = _cache_key(ic.item)
        if !(key in current_keys)
            rm(path; force=true)
            removed += 1
        end
    end

    return removed
end

# ── Per-component index directory structure ───

"""
    component_index_dir() -> String

Return the base directory for per-component coverage indices.

Indices are stored under `.testimonial/components/<component_name>/index.jls`.
"""
function component_index_dir()::String
    return joinpath(".testimonial", "components")
end

"""
    component_index_path(component::String) -> String

Return the path to a component's coverage index file.

Returns `.testimonial/components/<component>/index.jls`.
"""
function component_index_path(component::String)::String
    return joinpath(component_index_dir(), component, "index.jls")
end

"""
    save_routing(dir::AbstractString, components::Vector{Symbol}) -> Nothing

Save a routing file at `<dir>/index.jls` enumerating available components.

The routing file is a serialized `Vector{Symbol}` that lists all component
names whose indices are stored under `<dir>/components/<name>/`.

Creates parent directories if needed and writes atomically.
"""
function save_routing(dir::AbstractString, components::Vector{Symbol})::Nothing
    routing_path = joinpath(String(dir), "index.jls")
    mkpath(String(dir))
    tmppath = routing_path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, components)
    end
    mv(tmppath, routing_path; force=true)
    return nothing
end

"""
    load_routing(dir::AbstractString) -> Vector{Symbol}

Load the routing file from `<dir>/index.jls`.

Returns the list of available component names, or an empty vector if no
routing file exists, is corrupted, or deserialization fails.
"""
function load_routing(dir::AbstractString)::Vector{Symbol}
    routing_path = joinpath(String(dir), "index.jls")
    if !isfile(routing_path)
        return Symbol[]
    end
    try
        result = open(deserialize, routing_path, "r")
        if result isa Vector{Symbol}
            return result
        end
        return Symbol[]
    catch
        return Symbol[]
    end
end

export component_index_dir, component_index_path, save_routing, load_routing

end # module IndexBuilder