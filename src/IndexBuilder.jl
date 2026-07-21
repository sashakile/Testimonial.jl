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

    # Build component graph from coverage data
    edges = _build_component_graph(parent, item_map, path_map)

    # Save component graph alongside routing file
    _save_graph_file(edges)

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

    # Build and save per-component indices with component graph
    for (comp_name, pairs) in comp_groups
        comp_map = Dict{typeof(first(pairs).first), typeof(first(pairs).second)}()
        for (ref, ic) in pairs
            comp_map[ref] = ic
        end

        comp_index = parent.CoverageIndex(
            comp_map, git_sha, string(VERSION), v"0.1.0", now(), "", edges
        )
        comp_path = parent.component_index_path(comp_name)
        save_index(comp_index, comp_path)

        # Compute and save dependency fingerprint for this component
        if comp_name != "__unmapped__"
            fp = compute_dependency_fingerprint(comp_name, path_map, edges, project_dir)
            save_fingerprint(comp_name, fp)
        end
    end

    # Save routing file with all component names (excluding unmapped)
    component_names = [Symbol(k) for k in keys(comp_groups) if k != "__unmapped__"]
    save_routing(".testimonial", component_names)

    return nothing
end

"""
    _save_graph_file(edges::Dict{String, Set{String}}) -> Nothing

Save the component graph to `.testimonial/graph.jls` alongside the routing file.

Creates the .testimonial directory if needed.
"""
function _save_graph_file(edges::Dict{String, Set{String}})::Nothing
    mkpath(".testimonial")
    tmppath = joinpath(".testimonial", "graph.jls.tmp")
    graph_path = joinpath(".testimonial", "graph.jls")
    open(tmppath, "w") do io
        serialize(io, edges)
    end
    mv(tmppath, graph_path; force=true)
    return nothing
end

"""
    save_component_graph(edges::Dict{String, Set{String}}) -> Nothing

Save the component graph to `.testimonial/graph.jls`.

Public API for saving inter-component dependency edges.
"""
function save_component_graph(edges::Dict{String, Set{String}})::Nothing
    _save_graph_file(edges)
    return nothing
end

"""
    load_component_graph() -> Dict{String, Set{String}}

Load the component graph from `.testimonial/graph.jls`.

Returns an empty dict if the file doesn't exist, is corrupted, or
deserialization fails.
"""
function load_component_graph()::Dict{String, Set{String}}
    graph_path = joinpath(".testimonial", "graph.jls")
    if !isfile(graph_path)
        return Dict{String, Set{String}}()
    end
    try
        result = open(deserialize, graph_path, "r")
        if result isa Dict{String, Set{String}}
            return result
        end
        return Dict{String, Set{String}}()
    catch
        return Dict{String, Set{String}}()
    end
end

"""
    _build_component_graph(parent, item_map, path_map) -> Dict{String, Set{String}}

Build inter-component dependency edges from coverage data.

For each item in the index, examines its covered source files. If a test
in component B covers a file in component A, records edge B → A.

Returns a dict mapping each component to the set of components it depends on.
"""
function _build_component_graph(
    parent::Module,
    item_map::Dict,
    path_map::Dict{Symbol, String}
)::Dict{String, Set{String}}
    edges = Dict{String, Set{String}}()

    for (ref, ic) in item_map
        # Determine test's component
        test_comp = if ref.component != ""
            ref.component
        else
            result = parent.component_of(ref.file, path_map)
            result === nothing ? nothing : string(result)
        end
        test_comp === nothing && continue

        # Check each source file this test covers
        for (src_file, _) in ic.source_files
            src_comp = parent.component_of(src_file, path_map)
            src_comp === nothing && continue
            src_comp_str = string(src_comp)

            # If cross-component: test component depends on source component
            if src_comp_str != test_comp
                if !haskey(edges, test_comp)
                    edges[test_comp] = Set{String}()
                end
                push!(edges[test_comp], src_comp_str)
            end
        end
    end

    return edges
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

    parent = Base.parentmodule(@__MODULE__)

    # First pass: try deserializing as a flat CoverageIndex (old format)
    try
        result = open(deserialize, p, "r")
        if result isa parent.CoverageIndex
            return result
        end
        # If it's a Vector{Symbol}, it's a routing file — proceed to load per-component
        if result isa Vector{Symbol}
            return _load_per_component_indices(parent, result)
        end
        return nothing
    catch
        return nothing
    end
end

"""
    _load_per_component_indices(parent, components::Vector{Symbol}) -> CoverageIndex

Load per-component CoverageIndex files and merge them into a single index.

Reads each component's index from `.testimonial/components/<name>/index.jls`
and merges all items into a flat CoverageIndex. Components without an index
file are silently skipped.

Returns an empty CoverageIndex if no component indices can be loaded.
"""
function _load_per_component_indices(parent::Module, components::Vector{Symbol})::Any
    merged_items = Dict{parent.TestItemRef, parent.ItemCoverage}()
    merged_git_hash = ""
    merged_julia_version = string(VERSION)
    merged_created_at = now()
    merged_edges = Dict{String, Set{String}}()

    for comp in components
        comp_path = parent.component_index_path(string(comp))
        if !isfile(comp_path)
            continue
        end

        try
            comp_index = open(deserialize, comp_path, "r")
            if comp_index isa parent.CoverageIndex
                for (ref, ic) in comp_index.items
                    merged_items[ref] = ic
                end
                # Use the most recent created_at
                if comp_index.created_at > merged_created_at
                    merged_created_at = comp_index.created_at
                end
                # Use the first non-empty git_hash found
                if isempty(merged_git_hash) && !isempty(comp_index.git_hash)
                    merged_git_hash = comp_index.git_hash
                end
                # Capture the first non-empty component graph.
                # Invariant: all per-component indices share the same full
                # inter_component_edges (the graph is built once and saved
                # identically to each). Taking the first non-empty one is safe.
                if isempty(merged_edges) && !isempty(comp_index.inter_component_edges)
                    merged_edges = comp_index.inter_component_edges
                end
            end
        catch
            continue
        end
    end

    return parent.CoverageIndex(
        merged_items, merged_git_hash, merged_julia_version, v"0.1.0",
        merged_created_at, "", merged_edges
    )
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

export component_index_dir, component_index_path, save_routing, load_routing,
       migrate_index

"""
    migrate_index(testimonial_dir::AbstractString, project_dir::AbstractString) -> Nothing

Migrate a flat CoverageIndex to the per-component layout.

Reads the old flat index from `<testimonial_dir>/index.jls`, groups items by
component (using `component_paths` and `component_of`), writes per-component
indices to `<testimonial_dir>/components/<name>/index.jls`, and writes
the routing file at `<testimonial_dir>/index.jls`.

If the index is already migrated (routing file exists), this is a no-op.
If no Project.toml exists, items are saved under a single default component.
"""
function migrate_index(testimonial_dir::AbstractString, project_dir::AbstractString)::Nothing
    testimonial_dir = String(testimonial_dir)
    project_dir = String(project_dir)
    parent = Base.parentmodule(@__MODULE__)

    routing_path = joinpath(testimonial_dir, "index.jls")

    # Check if already migrated (routing file is a Vector{Symbol})
    if isfile(routing_path)
        try
            existing = open(deserialize, routing_path, "r")
            if existing isa Vector{Symbol}
                return nothing  # Already migrated
            end
        catch
            # Corrupted or old format — proceed with migration
        end
    end

    # Load the flat index (old format or direct path)
    flat_index = if isfile(routing_path)
        try
            result = open(deserialize, routing_path, "r")
            result isa parent.CoverageIndex ? result : nothing
        catch
            nothing
        end
    else
        nothing
    end

    flat_index === nothing && return nothing

    # Discover components
    path_map = parent.component_paths(project_dir)
    abs_project_dir = abspath(project_dir)

    # Group items by component
    comp_groups = Dict{String, Vector{Pair{Any, Any}}}()
    for (ref, ic) in flat_index.items
        comp = if ref.component != ""
            ref.component
        else
            # Resolve file to absolute path for component matching
            abs_file = isabspath(ref.file) ? ref.file : joinpath(abs_project_dir, ref.file)
            result = isempty(path_map) ? nothing : parent.component_of(abs_file, path_map)
            result === nothing ? "__unmapped__" : string(result)
        end

        if !haskey(comp_groups, comp)
            comp_groups[comp] = Pair{Any, Any}[]
        end
        push!(comp_groups[comp], ref => ic)
    end

    # Build component graph from coverage data (before the loop — fingerprints need it)
    edges = isempty(path_map) ? Dict{String, Set{String}}() : _build_component_graph(parent, flat_index.items, path_map)

    # Build and save per-component indices
    comp_dir = joinpath(testimonial_dir, "components")
    for (comp_name, pairs) in comp_groups
        comp_map = Dict{typeof(first(pairs).first), typeof(first(pairs).second)}()
        for (ref, ic) in pairs
            comp_map[ref] = ic
        end

        comp_idx_path = joinpath(comp_dir, comp_name, "index.jls")
        comp_index = parent.CoverageIndex(
            comp_map,
            flat_index.git_hash,
            flat_index.julia_version,
            flat_index.schema_version,
            flat_index.created_at,
            flat_index.environment_fingerprint,
        )
        save_index(comp_index, comp_idx_path)

        # Compute and save dependency fingerprint during migration
        if comp_name != "__unmapped__" && !isempty(path_map)
            fp = compute_dependency_fingerprint(comp_name, path_map, edges, String(project_dir))
            save_fingerprint(comp_name, fp)
        end
    end

    # Save routing file (excluding unmapped)
    component_names = [Symbol(k) for k in keys(comp_groups) if k != "__unmapped__"]
    save_routing(testimonial_dir, component_names)

    # Save component graph alongside routing file
    _save_graph_file(edges)

    return nothing
end

"""
    build_component_graph!(index::CoverageIndex, path_map::Dict{Symbol, String}) -> Dict{String, Set{String}}

Compute inter-component edges from a CoverageIndex's coverage data.

For each test item, examines its recorded `source_files`. When a test in
component B covers a file in component A, records edge B → A.
Intra-component coverage is ignored.

Returns a dict mapping each component to the set of components it depends on.
The caller should assign this to `index.inter_component_edges` when creating
a new CoverageIndex (note: CoverageIndex is immutable, so this function
returns the dict rather than mutating in place).
"""
function build_component_graph!(index, path_map::Dict{Symbol, String})::Dict{String, Set{String}}
    parent = Base.parentmodule(@__MODULE__)
    return _build_component_graph(parent, index.items, path_map)
end

# ── Dependency fingerprint computation ──────────

"""
    _find_transitive_deps(component_name, edges) -> Set{String}

Find all transitive dependencies of a component, including itself.

`edges[B] = Set([A, C])` means B depends on A and C.
`_find_transitive_deps("B", edges)` returns `Set(["B", "A", "C"])`.
"""
function _find_transitive_deps(component_name::String, edges::Dict{String, Set{String}})::Set{String}
    deps = Set{String}([component_name])
    queue = [component_name]

    while !isempty(queue)
        comp = popfirst!(queue)
        if haskey(edges, comp)
            for dep in edges[comp]
                if dep ∉ deps
                    push!(deps, dep)
                    push!(queue, dep)
                end
            end
        end
    end

    return deps
end

"""
    compute_dependency_fingerprint(component_name, path_map, edges, project_dir) -> String

Compute the dependency fingerprint for a component.

The fingerprint is the SHA-256 hash of all source files (`.jl` files under
`src/`) in the component's transitive dependency closure, combined with the
environment fingerprint (Julia version + Project.toml hash).

This is used at query time to detect whether a component's dependencies have
changed: if the stored fingerprint matches the current fingerprint, the cached
selection can be reused.

Returns a 64-character hex string (SHA-256).
"""
function compute_dependency_fingerprint(
    component_name::String,
    path_map::Dict{Symbol, String},
    edges::Dict{String, Set{String}},
    project_dir::String,
)::String
    parent = Base.parentmodule(@__MODULE__)

    # Step 1: Find all transitive dependencies (including the component itself)
    deps = _find_transitive_deps(component_name, edges)

    # Step 2: Collect all source files from these components
    source_files = String[]
    for (comp, ws_path) in path_map
        comp_str = string(comp)
        if comp_str in deps
            src_dir = joinpath(ws_path, "src")
            if isdir(src_dir)
                append!(source_files, parent._walk_jl_files(src_dir))
            end
        end
    end

    # Step 3: Hash all source files (sorted by path for determinism)
    hasher = SHA.SHA256_CTX()
    for f in sort(source_files)
        content = read(f)
        SHA.update!(hasher, content)
    end

    # Step 4: Include environment fingerprint
    env_fp = parent.compute_environment_fingerprint(project_dir)
    SHA.update!(hasher, codeunits(env_fp))

    return bytes2hex(SHA.digest!(hasher))
end

"""
    save_fingerprint(component_name::String, fingerprint::String) -> Nothing

Save the dependency fingerprint for a component to
`.testimonial/components/<component_name>/fingerprint.jls`.

Creates parent directories if needed and writes atomically.
"""
function save_fingerprint(component_name::String, fingerprint::String)::Nothing
    fp_path = joinpath(".testimonial", "components", component_name, "fingerprint.jls")
    mkpath(dirname(fp_path))
    tmppath = fp_path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, fingerprint)
    end
    mv(tmppath, fp_path; force=true)
    return nothing
end

"""
    load_fingerprint(component_name::String) -> Union{String, Nothing}

Load the dependency fingerprint for a component from
`.testimonial/components/<component_name>/fingerprint.jls`.

Returns `nothing` if the file doesn't exist, is corrupted, or
deserialization fails.
"""
function load_fingerprint(component_name::String)::Union{String, Nothing}
    fp_path = joinpath(".testimonial", "components", component_name, "fingerprint.jls")
    if !isfile(fp_path)
        return nothing
    end
    try
        result = open(deserialize, fp_path, "r")
        if result isa String
            return result
        end
        return nothing
    catch
        return nothing
    end
end

export migrate_index, build_component_graph!,
       save_component_graph, load_component_graph,
       compute_dependency_fingerprint, save_fingerprint, load_fingerprint

end # module IndexBuilder