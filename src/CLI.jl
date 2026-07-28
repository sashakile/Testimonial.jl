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
using Serialization
import ..Testimonial: CoverageIndex, TestItemRef, ItemCoverage,
    discover_testitems, load_incidents, save_incidents

export index_info, explain, run, main, SCHEMA_VERSION, STALE_INDEX_THRESHOLD_HOURS,
       format_reason, format_impact_result,
       _write_shard_files, _read_shard_manifest, _clean_shard_files

# ── Constants ──────────────────────────────────

"""Current schema version for CoverageIndex. Bump on breaking changes."""
const SCHEMA_VERSION = 2

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

    # Load promotion readiness info
    incidents = parent.load_incidents()
    candidate_count = count(i -> i.status == parent.Candidate, incidents)
    promoted_count = count(i -> i.status == parent.Promoted, incidents)
    manual_edges = parent.load_manual_edges()
    manual_edge_count = length(manual_edges)

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
        candidate_count = candidate_count,
        promoted_count = promoted_count,
        manual_edge_count = manual_edge_count,
    )
end

# ── Reason-chain display (PROV-001) ───────────────────────────────────────────

"""
    format_reason(reason::ImpactReason) -> Vector{String}

Render a single `ImpactReason` as human-readable lines: a header line
(`[KIND] description`) followed by one indented line per `ProvenanceLink`
in `reason.chain` (`└ [LAYER] content_unit: detail`).

These formatters are the display building blocks for dry-run selection
output (ticket testimonial-q68n) and the `--layers` explain view.
"""
function format_reason(reason)::Vector{String}
    lines = String["[$(reason.kind)] $(reason.description)"]
    for link in reason.chain
        # Walk the next-pointer linked list: each ProvenanceLink may chain
        # to a deeper link (PROV-001 multi-hop path).
        node = link
        while node !== nothing
            push!(lines, "  └ [$(node.layer)] $(node.content_unit): $(node.detail)")
            node = node.next
        end
    end
    return lines
end

"""
    format_impact_result(result::ImpactResult) -> Vector{String}

Render an `ImpactResult` as human-readable lines: an item header
(annotated with selected/unselected status) followed by each reason
rendered via `format_reason`.
"""
function format_impact_result(result)::Vector{String}
    lines = String[]
    status = result.selected ? "selected" : "not selected"
    push!(lines, "$(result.item.name)  ($(result.item.file))  [$status]")
    if result.fallback_reason !== nothing
        push!(lines, "  fallback: $(result.fallback_reason)")
    end
    for reason in result.reasons
        append!(lines, format_reason(reason))
    end
    return lines
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
          test_dirs::Vector{String}=String["test/"],
          project_dir::Union{String,Nothing}=nothing) -> Union{Symbol, Vector}

Run the smart test selection pipeline.

Loads the coverage index, checks staleness, parses git diff against
`base_ref`, queries the index, and returns either:
- `:full_suite` — fallback signal (missing/stale index, Project.toml changes,
  coverage gaps, or always-run file changed)
- `Vector{TestItemRef}` — the selected items to run

When the index has component data (non-empty `inter_component_edges`),
runs per-component queries in parallel using `Threads.@threads`.
Only components that transitively depend on changed code are searched.

# Pipeline
1. Load index — `:full_suite` if missing
2. Check staleness — `:full_suite` if stale
3. Get git diff — `:full_suite` if diff fails or is empty
4. Check for suite-trigger files (Project.toml, Manifest.toml)
5. Check for always-run prefixes (runtests.jl)
6. Resolve affected components (bottom-up) — returns empty list if no components are affected
7. Run per-component queries in parallel (component mode) or single query (flat mode)
8. Check coverage gaps — `:full_suite` if gaps exist
9. Return selected items
"""
function run(; base_ref::String="origin/main",
               index_path::String=".testimonial/index.jls",
               test_dirs::Vector{String}=String["test/"],
               project_dir::Union{String,Nothing}=nothing,
               n_shards::Int=0,
               shadow::Bool=false,
               auto_ingest::Bool=false)::Union{Symbol, Vector}
    parent = Base.parentmodule(@__MODULE__)

    # Step 0: Generate run_key for idempotent ingestion
    run_key = _make_run_key()

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

    # Step 2a: Check environment fingerprint
    proj_dir = project_dir !== nothing ? String(project_dir) : _git_repo_root()
    current_fp = parent.compute_environment_fingerprint(proj_dir)
    if !parent.environment_matches(index, current_fp)
        @warn "Environment fingerprint mismatch — running full suite"
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

    # Step 6: Determine if component-aware mode
    component_edges = if !isempty(index.inter_component_edges)
        index.inter_component_edges
    else
        loaded = parent.load_component_graph()
        isempty(loaded) ? nothing : loaded
    end

    abs_test_dirs = [isabspath(d) ? d : abspath(d) for d in test_dirs]

    if component_edges !== nothing
        # Step 6a: Load component path map
        proj_root = project_dir !== nothing ? String(project_dir) : _git_repo_root()
        path_map = parent.component_paths(proj_root)

        if isempty(path_map)
            # Project.toml missing — fall back to flat mode
            @warn "No components discovered — falling back to flat mode"
            selected = parent.query_files(index, changed_files)
            filtered = [
                item for item in selected
                if any(startswith(item.item.file, d) for d in abs_test_dirs)
            ]
        else
            filtered = _run_component_aware(
                index, changed, changed_files, abs_test_dirs, path_map, component_edges, proj_root,
            )
        end
    else
        # Step 6: Flat mode — single query
        selected = parent.query_files(index, changed_files)
        filtered = [
            item for item in selected
            if any(startswith(item.item.file, d) for d in abs_test_dirs)
        ]
    end

    # Step 6a: Merge manual edges into selection
    if filtered isa Vector && !isempty(changed_files)
        manual_results = parent.manual_edge_provider(index, changed_files)
        for r in manual_results
            if r.selected && any(startswith(r.item.file, d) for d in abs_test_dirs)
                # Avoid duplicates: if already in filtered, merge reasons
                existing_idx = findfirst(x -> x.item == r.item, filtered)
                if existing_idx !== nothing
                    merged = ImpactResult(
                        filtered[existing_idx].item,
                        vcat(filtered[existing_idx].reasons, r.reasons),
                        true,
                    )
                    filtered[existing_idx] = merged
                else
                    push!(filtered, r)
                end
            end
        end
    end

    # Step 6c: Merge runtime edges into selection
    if filtered isa Vector && !isempty(changed_files)
        runtime_results = parent.runtime_edge_provider(index, changed_files)
        for r in runtime_results
            if r.selected && any(startswith(r.item.file, d) for d in abs_test_dirs)
                # Avoid duplicates: if already in filtered, merge reasons
                existing_idx = findfirst(x -> x.item == r.item, filtered)
                if existing_idx !== nothing
                    merged = ImpactResult(
                        filtered[existing_idx].item,
                        vcat(filtered[existing_idx].reasons, r.reasons),
                        true,
                    )
                    filtered[existing_idx] = merged
                else
                    push!(filtered, r)
                end
            end
        end
    end

    # Step 6d: Merge external input changes into selection
    if filtered isa Vector && !isempty(changed_files)
        ext_results = parent.external_input_provider(index, changed_files)
        for r in ext_results
            if r.selected && any(startswith(r.item.file, d) for d in abs_test_dirs)
                existing_idx = findfirst(x -> x.item == r.item, filtered)
                if existing_idx !== nothing
                    merged = ImpactResult(
                        filtered[existing_idx].item,
                        vcat(filtered[existing_idx].reasons, r.reasons),
                        true,
                    )
                    filtered[existing_idx] = merged
                else
                    push!(filtered, r)
                end
            end
        end
    end

    # Step 6b: Merge always-run tests into selection
    if filtered isa Vector
        always_run_tests = parent.get_always_run_tests()
        for (file, name) in always_run_tests
            # Check if already in selection
            existing_idx = findfirst(x -> x.item.file == file && x.item.name == name, filtered)
            if existing_idx !== nothing
                # Already selected — add AlwaysRun reason
                reason = parent.ImpactReason(parent.AlwaysRun, "always-run: test has recent failures")
                merged = parent.ImpactResult(
                    filtered[existing_idx].item,
                    vcat(filtered[existing_idx].reasons, [reason]),
                    true,
                )
                filtered[existing_idx] = merged
            else
                # Find in index to get full TestItemRef
                ref = nothing
                for (r, _) in index.items
                    if r.file == file && r.name == name
                        ref = r
                        break
                    end
                end
                if ref === nothing
                    ref = parent.TestItemRef(file, 0, name)
                end
                # Only include if in test directories
                if any(startswith(file, d) for d in abs_test_dirs)
                    reason = parent.ImpactReason(parent.AlwaysRun, "always-run: test has recent failures")
                    push!(filtered, parent.ImpactResult(ref, [reason]))
                end
            end
        end
    end

    # Step 7: Check coverage gaps in changed source files
    source_files = [f for f in changed_files
                    if endswith(f, ".jl") && !any(startswith(f, d) for d in abs_test_dirs)]
    if !isempty(source_files)
        source_changed = Dict{String, Set{Int}}(
            f => get(changed, f, Set{Int}()) for f in source_files
        )
        gaps = parent.coverage_gaps(index, source_changed)
        if !isempty(gaps)
            @warn "Coverage gaps detected in source files — running full suite"
            return :full_suite
        end
    end

    # Step 8: Write shard files if requested
    if n_shards > 0 && filtered isa Vector && !isempty(filtered)
        items = [r.item for r in filtered]
        parent = Base.parentmodule(@__MODULE__)
        history = parent.load_run_history()
        durations = parent.read_durations(history)
        _write_shard_files(items, n_shards, durations)
    elseif n_shards > 0
        # No items selected — write empty shards
        _write_shard_files(TestItemRef[], n_shards, Dict{Tuple{String, String}, Float64}())
    end

    # Step 9: Shadow mode — log selection and run all tests
    if shadow
        n_selected = filtered isa Vector ? length(filtered) : 0
        @info "Shadow mode: selected $n_selected items, running full suite"
        return :full_suite
    end

    # Step 10: Auto-ingest — post-run coverage ingestion
    if auto_ingest
        @info "Auto-ingest: recording run_key=$run_key for runtime feedback"
        parent.ingest(; run_key=run_key, index_path=index_path)
    end

    return filtered
end

"""
    _make_run_key() -> String

Generate a unique run key from the current git hash and timestamp.

Format: "<git_sha>_<unix_ms>". Used for idempotent ingestion (FEED-004).
"""
function _make_run_key()::String
    git_sha = try
        strip(read(`git rev-parse --short HEAD`, String))
    catch
        "nogit"
    end
    ts_ms = string(Dates.value(Dates.now()))
    return "$(git_sha)_$(ts_ms)"
end

# ── CLI entry point (main) ────────────────────────

"""
    main(args=ARGS)

Entry point for command-line invocation. Parses flags and calls `run()`.

# Flags
- `--shadow`: enable shadow mode (compute selection but run all tests)
- `--enforcing`: enable enforcing mode (return selected set)
- `--base-ref <ref>`: git base ref for diff (default: origin/main)
- `--n-shards <N>`: number of CI shards (default: 0)

The `--shadow` and `--enforcing` flags are mutually exclusive.
If neither flag is given, the mode is read from `Testimonial.toml`
`[safety] mode` key (defaults to `:shadow` if absent).

Unknown flags are silently ignored for forward compatibility.
"""
function main(args::Vector{String}=ARGS)
    # Check for subcommands
    if !isempty(args) && args[1] == "incidents"
        return _handle_incidents(args[2:end])
    end

    # Flag parsing for run()
    shadow = nothing  # nothing = use config default
    base_ref = "origin/main"
    n_shards = 0
    has_shadow_flag = false
    has_enforcing_flag = false

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--shadow"
            has_shadow_flag = true
            shadow = true
        elseif arg == "--enforcing"
            has_enforcing_flag = true
            shadow = false
        elseif arg == "--base-ref" && i + 1 <= length(args)
            base_ref = args[i + 1]
            i += 1
        elseif arg == "--n-shards" && i + 1 <= length(args)
            n_shards = parse(Int, args[i + 1])
            i += 1
        end
        i += 1
    end

    # If no explicit flag, read from config
    if !has_shadow_flag && !has_enforcing_flag
        par = Base.parentmodule(@__MODULE__)
        config = par.read_testimonial_config(_git_repo_root())
        mode = par.parse_safety_mode(config)
        shadow = (mode == :shadow)
    end

    return run(; base_ref=base_ref, n_shards=n_shards, shadow=shadow)
end

"""
    _handle_incidents(args) -> String

Handle the `incidents` subcommand.

- `incidents`: list all incidents
- `incidents dismiss <N>`: dismiss incident by 1-indexed position
"""
function _handle_incidents(args::Vector{String})::String
    incidents = load_incidents()

    if !isempty(args) && args[1] == "dismiss"
        if length(args) < 2
            return "Usage: testimonial incidents dismiss <index>"
        end
        idx = tryparse(Int, args[2])
        if idx === nothing || idx < 1 || idx > length(incidents)
            return "Invalid index: $idx (must be 1-$(length(incidents)))"
        end
        dismissed = incidents[idx]
        deleteat!(incidents, idx)
        save_incidents(incidents)
        return "Dismissed incident $idx: $(dismissed.changed_content) → $(dismissed.missed_test.name) [$(dismissed.status)]"
    end

    # List incidents
    if isempty(incidents)
        return "No incidents recorded."
    end

    lines = String[]
    push!(lines, "Incidents ($(length(incidents))):")
    for (i, inc) in enumerate(incidents)
        ts = Dates.format(inc.timestamp, "yyyy-mm-dd HH:MM")
        push!(lines, "  $i: [$(inc.status)] $(inc.changed_content) → $(inc.missed_test.name) ($ts)")
    end
    return join(lines, "
")
end

# ── Component-aware bottom-up resolution ────────

"""
    _resolve_affected_components(edges, changed_files, path_map) -> Set{String}

Resolve which components are affected by the given changed files,
using bottom-up traversal of the component dependency graph.

For each changed file, determines its owning component via
`component_of(file, path_map)`. Then for each affected component,
finds all components that transitively depend on it (using the
component graph's reverse edges).

Returns the set of affected component names (strings). Returns an
empty set if no changed files belong to any known component.

# Component graph convention
`edges[B] = Set([A, C])` means component B depends on A and C.
If A is changed, B (and components that depend on B) must be searched.
"""
function _resolve_affected_components(
    edges::Dict{String, Set{String}},
    changed_files::Vector{String},
    path_map::Dict{Symbol, String},
)::Set{String}
    parent = Base.parentmodule(@__MODULE__)

    # Step 1: Find which components own the changed files
    changed_components = Set{String}()
    for f in changed_files
        comp = parent.component_of(f, path_map)
        if comp !== nothing
            push!(changed_components, string(comp))
        end
    end

    isempty(changed_components) && return changed_components

    # Step 2: Build reverse edge map: component → set of components that depend on it
    reverse_edges = Dict{String, Set{String}}()
    for (dep, deps) in edges
        for d in deps
            if !haskey(reverse_edges, d)
                reverse_edges[d] = Set{String}()
            end
            push!(reverse_edges[d], dep)
        end
    end

    # Step 3: BFS from changed components along reverse edges
    affected = copy(changed_components)
    queue = collect(changed_components)
    visited = Set(changed_components)

    while !isempty(queue)
        comp = popfirst!(queue)
        if haskey(reverse_edges, comp)
            for dependent in reverse_edges[comp]
                if dependent ∉ visited
                    push!(visited, dependent)
                    push!(affected, dependent)
                    push!(queue, dependent)
                end
            end
        end
    end

    return affected
end

# ── Component-aware query orchestration ────────

"""
    _run_component_aware(index, changed, changed_files, abs_test_dirs, path_map, edges, project_dir) -> Vector{ImpactResult}

Run per-component queries in parallel for all components transitively
affected by the changed files.

Resolves the affected component set via `_resolve_affected_components`,
then runs per-component queries using `Threads.@threads`. Before running
each query, checks the selection cache: if the component's dependency
fingerprint matches the cached value, the cached results are reused and
the query is skipped.

Results are merged and filtered to only include items in test directories.

Returns an empty `ImpactResult[]` if no components are affected.
"""
function _run_component_aware(
    index,
    changed::Dict{String, Set{Int}},
    changed_files::Vector{String},
    abs_test_dirs::Vector{String},
    path_map::Dict{Symbol, String},
    edges::Dict{String, Set{String}},
    project_dir::String,
)::Vector
    parent = Base.parentmodule(@__MODULE__)

    # Resolve affected components (bottom-up)
    affected = _resolve_affected_components(edges, changed_files, path_map)

    if isempty(affected)
        return parent.ImpactResult[]
    end

    # Run per-component queries in parallel
    comps = collect(affected)
    n_comps = length(comps)
    comp_results = Vector{Union{Vector, Nothing}}(undef, n_comps)

    Threads.@threads for i in 1:n_comps
        comp = comps[i]

        # Check selection cache: skip query if fingerprint unchanged
        cached = parent.load_selection_cache(comp)
        current_fp = parent.compute_dependency_fingerprint(comp, path_map, edges, project_dir)

        if cached !== nothing && cached[1] == current_fp
            comp_results[i] = cached[2]
        else
            results = parent.query(
                [parent.direct_change_provider, parent.unresolved_provider],
                index,
                changed;
                component=comp,
            )
            # Cache the fresh results
            parent.save_selection_cache(comp, current_fp, results)
            comp_results[i] = results
        end
    end

    # Merge results and filter by test directories
    selected = parent.ImpactResult[]
    for i in 1:n_comps
        results = comp_results[i]
        if results !== nothing
            for r in results
                if r.selected && any(startswith(r.item.file, d) for d in abs_test_dirs)
                    push!(selected, r)
                end
            end
        end
    end

    return selected
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
        return String(strip(result))
    catch
        return "."
    end
end

# ── Shard file helpers ──────────────────────────

"""
    _write_shard_files(items, n_shards, durations=Dict())

Write balanced shard files to `.testimonial/shard_<N>.jls`.

Each shard file contains a serialized `Vector{TestItemRef}` for
consumption by a CI worker. Also writes a manifest file at
`.testimonial/shard_manifest.jls` listing all shard file paths.
"""
function _write_shard_files(
    items::Vector{TestItemRef},
    n_shards::Int,
    durations::Dict{Tuple{String, String}, Float64}=Dict{Tuple{String, String}, Float64}(),
)::Nothing
    parent = Base.parentmodule(@__MODULE__)

    # Clean any previous shard files
    _clean_shard_files()

    mkpath(".testimonial")

    # Balance shards
    shards = parent.balance_shards(items, durations, n_shards)

    # Write each shard
    shard_paths = String[]
    for i in 1:n_shards
        shard_path = joinpath(".testimonial", "shard_$(i).jls")
        tmppath = shard_path * ".tmp"
        open(tmppath, "w") do io
            serialize(io, shards[i])
        end
        mv(tmppath, shard_path; force=true)
        push!(shard_paths, shard_path)
    end

    # Write manifest
    manifest_path = joinpath(".testimonial", "shard_manifest.jls")
    tmppath = manifest_path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, shard_paths)
    end
    mv(tmppath, manifest_path; force=true)

    return nothing
end

"""
    _read_shard_manifest() -> Vector{String}

Read the shard manifest file listing all shard file paths.

Returns an empty vector if no manifest exists or it cannot be read.
"""
function _read_shard_manifest()::Vector{String}
    manifest_path = joinpath(".testimonial", "shard_manifest.jls")
    if !isfile(manifest_path)
        return String[]
    end
    try
        result = open(deserialize, manifest_path, "r")
        if result isa Vector{String}
            return result
        end
        return String[]
    catch
        return String[]
    end
end

"""
    _load_shard(n::Int) -> Vector{TestItemRef}

Load a shard file by its 1-indexed number.

Returns an empty vector if the file doesn't exist or can't be read.
"""
function _load_shard(n::Int)::Vector{TestItemRef}
    shard_path = joinpath(".testimonial", "shard_$(n).jls")
    if !isfile(shard_path)
        return TestItemRef[]
    end
    try
        result = open(deserialize, shard_path, "r")
        if result isa Vector{TestItemRef}
            return result
        end
        return TestItemRef[]
    catch
        return TestItemRef[]
    end
end

"""
    _clean_shard_files()

Remove all shard files and the shard manifest.
"""
function _clean_shard_files()::Nothing
    # Remove any existing shard files from manifest
    existing = _read_shard_manifest()
    for path in existing
        if isfile(path)
            rm(path; force=true)
        end
    end

    # Also remove the manifest itself
    manifest_path = joinpath(".testimonial", "shard_manifest.jls")
    if isfile(manifest_path)
        rm(manifest_path; force=true)
    end

    # Clean up any orphaned shard files (in case manifest is stale)
    testimonial_dir = ".testimonial"
    if isdir(testimonial_dir)
        for entry in readdir(testimonial_dir)
            if startswith(entry, "shard_") && endswith(entry, ".jls")
                rm(joinpath(testimonial_dir, entry); force=true)
            end
        end
    end

    return nothing
end

end # module CLI