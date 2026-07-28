module Testimonial

using Dates
using SHA
using Serialization
using TOML

# ════════════════════════════════════════════
# 1. Core types — no dependencies on sub-modules
# ════════════════════════════════════════════

export TestItemRef, ImpactReasonKind, ImpactReason,
       ImpactResult, CoverageGap, ItemCoverage, CoverageIndex,
       DirectChange, DependencyChange, AlwaysRun, Unresolved,
       LayerKind, COVERAGE, INFERRED, STATIC, TEST_FILE_CHANGED, MANUAL,
       ProvenanceLink,
       AlwaysRunReason, LAST_RUN_FAILED, NEWLY_ADDED, NO_HISTORY, MUST_RUN, QUARANTINED,
       IncidentStatus, Candidate, Promoted, Dismissed,
       MissedSelectionIncident,
       DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD,
       consecutive_passes, record_run, should_evict, reset_always_run_state,
       get_always_run_tests,
       RunEntry, RunHistoryEntry, RunHistory, record_duration!, read_durations,
       record_outcome_history!, get_outcome_history,
       ingest, cov_lines, prune_ingested_run_keys,
       save_run_history, load_run_history, DEFAULT_RUN_HISTORY_PATH,
       INCIDENTS_PATH, save_incidents, load_incidents, append_incident,
       compare_selection_vs_outcomes, promote_incidents,
       reconcile,
       record_outcome, get_outcome_history, reset_flaky_history,
       is_flaky, quarantine_test, unquarantine_test, get_quarantined_tests,
       auto_quarantine_flaky, clear_quarantine_on_consistent,
       MANUAL_EDGES_PATH, ManualEdge, save_manual_edges, load_manual_edges,
       create_manual_edges_from_promoted, manual_edge_provider,
       balance_shards,
       compute_environment_fingerprint, environment_matches,
       MustRunRule, matches_must_run_rule, must_run_tags, parse_must_run_rules,
       parse_safety_mode,
       scoped_fallback, collect_fallback_reasons, must_run_with_fallback_priority,
       SEED_FAULT_PATTERNS, run_seeded_fault_test, run_all_seeded_fault_tests,
       discover_components, component_of, component_paths,
       component_index_dir, component_index_path, save_routing, load_routing,
       select_changed_items, _discover_in_file,
       read_testimonial_config, parse_components_override

# ── Enums (defined before structs that reference them) ──

"""Why a test is unconditionally included in the selection (always-run set)."""
@enum AlwaysRunReason begin
    LAST_RUN_FAILED
    NEWLY_ADDED
    NO_HISTORY
    MUST_RUN
    QUARANTINED
end

"""Status of a missed-selection incident."""
@enum IncidentStatus begin
    Candidate
    Promoted
    Dismissed
end

# ── Basic structs ──────────────────────────────

"""Reference to a single @testitem in a source file."""
struct TestItemRef
    file :: String
    line :: Int
    name :: String
    tags :: Vector{Symbol}
    file_hash :: String
    always_run_reason :: Union{Nothing, AlwaysRunReason}
    component :: String
    external_inputs :: Vector{String}
end

# Convenience constructor without tags, file_hash, always_run_reason, component, external_inputs
TestItemRef(file, line, name) = TestItemRef(file, line, name, Symbol[], "", nothing, "", String[])

# Convenience constructor without always_run_reason, component, external_inputs
TestItemRef(file, line, name, tags, file_hash) = TestItemRef(file, line, name, tags, file_hash, nothing, "", String[])

# Convenience constructor without component, external_inputs
TestItemRef(file, line, name, tags, file_hash, always_run_reason) = TestItemRef(file, line, name, tags, file_hash, always_run_reason, "", String[])

# Convenience constructor without external_inputs
TestItemRef(file, line, name, tags, file_hash, always_run_reason, component) = TestItemRef(file, line, name, tags, file_hash, always_run_reason, component, String[])

# Equality by identity (file, name) — excludes line, tags, and file_hash
Base.:(==)(a::TestItemRef, b::TestItemRef) = a.file == b.file && a.name == b.name
Base.hash(r::TestItemRef, h::UInt) = hash(r.file, hash(r.name, h))

# ── Enums ──────────────────────────────────────

"""Why a test item was selected for execution."""
@enum ImpactReasonKind begin
    DirectChange
    DependencyChange
    AlwaysRun
    Unresolved
end

"""Source analysis layer that produced a provenance link.

Mirrors the five layers named in PROV-001
(openspec/changes/add-provenance-explainability/specs/provenance/spec.md):
coverage attribution, inferred edges, static analysis, test-file changes,
and manual overrides.
"""
@enum LayerKind begin
    COVERAGE
    INFERRED
    STATIC
    TEST_FILE_CHANGED
    MANUAL
end

"""A single link in a selection reason chain (PROV-001).

Fields:
- `layer::LayerKind` — the analysis layer that produced this link
- `content_unit::String` — normalized file path or method name
- `detail::String` — human-readable description
- `next::Union{Nothing, ProvenanceLink}` — the next link, forming a
  linked list traced from changed content unit to the selected test

Immutable and equal by structure. Construct with `ProvenanceLink(layer,
content_unit, detail, next)`; pass `nothing` for `next` to terminate the
chain.
"""
struct ProvenanceLink
    layer :: LayerKind
    content_unit :: String
    detail :: String
    next :: Union{Nothing, ProvenanceLink}
end

# Structural equality + hash so identical chains compare equal regardless
# of construction site (default struct == falls back to ===).
Base.:(==)(a::ProvenanceLink, b::ProvenanceLink) =
    a.layer == b.layer &&
    a.content_unit == b.content_unit &&
    a.detail == b.detail &&
    a.next == b.next
Base.hash(p::ProvenanceLink, h::UInt) =
    hash(p.layer, hash(p.content_unit, hash(p.detail, hash(p.next, h))))

# ── Reason and result types ────────────────────

"""A single reason why a test is affected.

Fields:
- `kind::ImpactReasonKind` — why the test was selected
- `description::String` — human-readable summary
- `chain::Vector{ProvenanceLink}` — reason chain tracing changed content
  unit to test (PROV-001). Empty by default; populated by the query
  layer when it traces a selection path.
"""
struct ImpactReason
    kind :: ImpactReasonKind
    description :: String
    chain :: Vector{ProvenanceLink}
end

# Backward-compat constructor: callers that don't build a chain get an empty one.
ImpactReason(kind::ImpactReasonKind, description::String) =
    ImpactReason(kind, description, ProvenanceLink[])

# Structural equality including the chain (default struct == is identity).
Base.:(==)(a::ImpactReason, b::ImpactReason) =
    a.kind == b.kind &&
    a.description == b.description &&
    a.chain == b.chain
Base.hash(r::ImpactReason, h::UInt) =
    hash(r.kind, hash(r.description, hash(r.chain, h)))

"""The result of an impact query for a single test item."""
struct ImpactResult
    item :: TestItemRef
    reasons :: Vector{ImpactReason}
    selected :: Bool
    fallback_reason :: Union{Nothing, String}
end

# Default: selected = true when reasons are present, fallback_reason = nothing
function ImpactResult(item::TestItemRef, reasons::Vector{ImpactReason})
    ImpactResult(item, reasons, !isempty(reasons), nothing)
end

# Convenience constructor without fallback_reason (for backward compat)
ImpactResult(item, reasons, selected) = ImpactResult(item, reasons, selected, nothing)

# ── Coverage types ─────────────────────────────

"""A contiguous range of uncovered lines in a source file."""
struct CoverageGap
    file :: String
    start_line :: Int
    end_line :: Int
end

"""A candidate or promoted missed-selection incident.

Records when a full run revealed a test failure that the most recent
selection would have skipped. Equality is based on (changed_content,
missed_test, status) — timestamp is excluded from identity.
"""
struct MissedSelectionIncident
    changed_content :: String
    missed_test :: TestItemRef
    timestamp :: DateTime
    status :: IncidentStatus
end

function Base.:(==)(a::MissedSelectionIncident, b::MissedSelectionIncident)
    return a.changed_content == b.changed_content &&
           a.missed_test == b.missed_test &&
           a.status == b.status
end

function Base.hash(a::MissedSelectionIncident, h::UInt)
    return hash(a.changed_content, hash(a.missed_test, hash(a.status, h)))
end

"""Coverage data for a single test item."""
struct ItemCoverage
    item :: TestItemRef
    covered_lines :: Vector{Int}
    uncovered_lines :: Vector{Int}
    source_files :: Dict{String, Tuple{Vector{Int}, Vector{Int}}}
end

"""The full coverage index for a project snapshot."""
struct CoverageIndex
    items :: Dict{TestItemRef, ItemCoverage}
    git_hash :: String
    julia_version :: String
    schema_version :: VersionNumber
    created_at :: DateTime
    environment_fingerprint :: String
    inter_component_edges :: Dict{String, Set{String}}
    runtime_edges :: Dict{TestItemRef, Vector{Tuple{String, Int}}}
    failed_item_count :: Int
    total_discovered_items :: Int
    available_layers :: Int
end

# Convenience constructor without environment_fingerprint and inter_component_edges
CoverageIndex(items, git_hash, julia_version, schema_version, created_at) =
    CoverageIndex(items, git_hash, julia_version, schema_version, created_at, "", Dict{String, Set{String}}(), Dict{TestItemRef, Vector{Tuple{String, Int}}}(), 0, 0, 1)

# Convenience constructor without inter_component_edges
CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint) =
    CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint, Dict{String, Set{String}}(), Dict{TestItemRef, Vector{Tuple{String, Int}}}(), 0, 0, 1)

# Convenience constructor without runtime_edges (for backward compat after adding runtime_edges)
CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint, ice) =
    CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint, ice, Dict{TestItemRef, Vector{Tuple{String, Int}}}(), 0, 0, 1)

# Convenience constructor without failed_item_count and total_discovered_items (for backward compat after adding recording metadata)
CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint, ice, runtime_edges) =
    CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint, ice, runtime_edges, 0, 0, 1)

# Ingest update constructor: preserve all metadata fields from source index
CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint, ice, runtime_edges, source) =
    CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint, ice, runtime_edges,
                  source.failed_item_count, source.total_discovered_items, source.available_layers)

# Convenience constructor without available_layers (for backward compat after adding layer metadata)
CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint, ice, runtime_edges, failed_item_count, total_discovered_items) =
    CoverageIndex(items, git_hash, julia_version, schema_version, created_at, fingerprint, ice, runtime_edges, failed_item_count, total_discovered_items, 1)

# ════════════════════════════════════════════
# ── Persistence ────────────────────────────────

export atomic_write, file_hash, extract_tags, discover_testitems

"""Write `data` to `path` atomically via temp-file + rename."""
function atomic_write(path::String, data::String)
    dir = dirname(path)
    mkpath(dir)
    tmppath = path * ".tmp"
    write(tmppath, data)
    mv(tmppath, path; force=true)
    return nothing
end

# ── ASTParser ────────────────────────────────

"""Regex matching @testitem "name" — shared across AST parsing and protocol resolution."""
const _TESTITEM_PATTERN = r"@testitem\s+\"([^\"]+)\""

"""Regex to extract external_inputs from @testitem annotations.

Matches: external_inputs=["file1", "file2", ...]
Captures the bracketed list content.
"""
const _EXTERNAL_INPUTS_PATTERN = r"external_inputs=\[([^\]]+)\]"

"""Compute SHA-256 hex prefix (first 12 chars) for a file's contents."""
function file_hash(path::String)::String
    content = read(path, String)
    return bytes2hex(sha256(content))[1:12]
end

"""
    _parse_tags(content::String) -> Dict{String, Vector{Symbol}}

Parse @testitem tag declarations from file content.
Shared by extract_tags and discover_testitems.
"""
function _parse_tags(content::String)::Dict{String, Vector{Symbol}}
    result = Dict{String, Vector{Symbol}}()
    pattern = r"@testitem\s+\"([^\"]+)\"(?:\s+tags=\[([^\]]*)\])?"
    for m in eachmatch(pattern, content)
        name = m.captures[1]
        tags_str = m.captures[2]
        if isnothing(tags_str) || isempty(strip(tags_str))
            result[name] = Symbol[]
        else
            tags = [Symbol(strip(strip(t), ':')) for t in split(tags_str, ",")]
            result[name] = tags
        end
    end
    return result
end

"""Extract tags declarations from @testitem blocks in a source file.

Returns a Dict mapping each @testitem name to its Vector{Symbol} of tags.
Items without a tags= declaration get an empty Symbol[].
"""
function extract_tags(path::String)::Dict{String, Vector{Symbol}}
    content = read(path, String)
    return _parse_tags(content)
end

"""Recursively walk a directory and return all .jl files."""
function _walk_jl_files(dir::String)::Vector{String}
    results = String[]
    for entry in sort(readdir(dir))
        path = joinpath(dir, entry)
        if isdir(path)
            append!(results, _walk_jl_files(path))
        elseif endswith(entry, ".jl")
            push!(results, path)
        end
    end
    return results
end

"""Discover @testitem blocks in all .jl files under the given directories.

Returns a Vector{TestItemRef} with one entry per @testitem found.
Search is recursive into subdirectories.
"""
function discover_testitems(dirs::Vector{String})::Vector{TestItemRef}
    items = TestItemRef[]
    for dir in dirs
        for path in _walk_jl_files(dir)
            content = read(path, String)
            fhash = bytes2hex(sha256(content))[1:12]
            tags = _parse_tags(content)
            for m in eachmatch(_TESTITEM_PATTERN, content)
                name = m.captures[1]
                offset = m.offset
                line = count(==('\n'), content[1:offset]) + 1
                item_tags = get(tags, name, Symbol[])
                item_external_inputs = _parse_external_inputs(content, offset)
                push!(items, TestItemRef(path, line, name, item_tags, fhash, nothing, "", item_external_inputs))
            end
        end
    end
    return items
end

"""Discover @testitem blocks in a single file.

Returns a Vector{TestItemRef} with one entry per @testitem found.
Returns an empty vector if the file cannot be read or contains no @testitems.
"""
function _discover_in_file(path::String)::Vector{TestItemRef}
    if !isfile(path)
        return TestItemRef[]
    end

    content = try
        read(path, String)
    catch
        return TestItemRef[]
    end

    fhash = bytes2hex(sha256(content))[1:12]
    tags = _parse_tags(content)
    items = TestItemRef[]

    for m in eachmatch(_TESTITEM_PATTERN, content)
        name = m.captures[1]
        offset = m.offset
        line = count(==('\n'), content[1:offset]) + 1
        item_tags = get(tags, name, Symbol[])

        # Extract external_inputs from the @testitem line and following context
        # Look in the surrounding 5 lines for an external_inputs declaration
        item_external_inputs = _parse_external_inputs(content, offset)

        push!(items, TestItemRef(path, line, name, item_tags, fhash, nothing, "", item_external_inputs))
    end

    return items
end

"""
    _parse_external_inputs(content::String, offset::Int) -> Vector{String}

Extract external_inputs declarations from the context around a @testitem.

Scans the @testitem line and the following lines (up to 5) for an
`external_inputs=[...]` declaration. Returns the list of file paths.
"""
function _parse_external_inputs(content::String, offset::Int)::Vector{String}
    # Get the substring from the @testitem start through the end of the line
    # (the @testitem declaration line — external_inputs is on the same line)
    content_end = length(content)
    # Find the end of this line
    line_end = findnext(isequal('\n'), content, offset)
    if line_end === nothing
        line_end = content_end
    else
        line_end = line_end - 1  # exclude newline
    end
    # Ensure valid UTF-8 indices
    offset = thisind(content, offset)
    line_end = min(line_end, content_end)
    line_end = thisind(content, line_end)
    context = content[offset:line_end]

    m = match(_EXTERNAL_INPUTS_PATTERN, context)
    if m === nothing
        return String[]
    end

    raw = m.captures[1]
    # Parse the bracketed list: ["file1", "file2", ...]
    paths = String[]
    for p in split(raw, ",")
        stripped = strip(p)
        # Remove quotes
        m2 = match(r"\"([^\"]+)\"", stripped)
        if m2 !== nothing
            push!(paths, m2.captures[1])
        end
    end
    return paths
end

"""
    select_changed_items(changed_files::Vector{String}, test_dirs::Vector{String}) -> Vector{TestItemRef}

Given a list of changed file paths (from git diff) and test directories,
return all @testitems in files that are under any of the test directories.

Files outside the test directories are ignored. Only files that actually
contain @testitem blocks contribute to the result.
"""
function select_changed_items(changed_files::Vector{String}, test_dirs::Vector{String})::Vector{TestItemRef}
    abs_dirs = String[]
    for d in test_dirs
        push!(abs_dirs, isabspath(d) ? realpath(d) : abspath(d))
    end

    items = TestItemRef[]
    seen = Set{String}()

    for cf in changed_files
        abs_cf = isabspath(cf) ? cf : abspath(cf)

        in_test_dir = false
        for d in abs_dirs
            if startswith(abs_cf, d)
                in_test_dir = true
                break
            end
        end

        if !in_test_dir
            continue
        end

        if abs_cf in seen
            continue
        end
        push!(seen, abs_cf)

        append!(items, _discover_in_file(abs_cf))
    end

    return items
end

# ── Environment fingerprint ─────────────────────

"""
    compute_environment_fingerprint(project_dir::String) -> String

Compute an environment fingerprint that captures the Julia version and
Project.toml contents. Used to detect environment changes that invalidate
the coverage index.

The fingerprint format is: "<julia_version>+<project_toml_hash>"
where project_toml_hash is the SHA-256 hex prefix (first 12 chars) of
Project.toml, or empty if Project.toml doesn't exist.
"""
function compute_environment_fingerprint(project_dir::String)::String
    proj_path = joinpath(project_dir, "Project.toml")
    proj_hash = if isfile(proj_path)
        bytes2hex(sha256(read(proj_path, String)))[1:12]
    else
        ""
    end
    return string(VERSION, "+", proj_hash)
end

"""
    environment_matches(index, expected_fp::String) -> Bool

Check whether the environment fingerprint in the coverage index matches
the expected fingerprint. Returns true if the index has no fingerprint
(empty string), since we cannot verify and should not block on old indexes.
"""
function environment_matches(index::CoverageIndex, expected_fp::String)::Bool
    if isempty(index.environment_fingerprint)
        return true  # Legacy index — can't verify, assume match
    end
    return index.environment_fingerprint == expected_fp
end

# ── Always-run set eviction tracking ──────────

"""Default number of consecutive passing runs before a test is evicted from the always-run set."""
const DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD = 5

# ── Must-run rules ──────────────────────────────

"""A rule that force-selects tests with a specific tag when a changed file matches a glob pattern."""
struct MustRunRule
    changed_glob :: String
    test_tag :: Symbol
end

"""
    matches_must_run_rule(rule::MustRunRule, changed_file::String) -> Bool

Check whether a changed file path matches a must-run rule's glob pattern.
Supports a single * wildcard in the pattern (matches any sequence of characters).
"""
function matches_must_run_rule(rule::MustRunRule, changed_file::String)::Bool
    pattern = rule.changed_glob
    star_idx = findfirst('*', pattern)
    if star_idx === nothing
        return changed_file == pattern
    end
    prefix = pattern[1:star_idx-1]
    suffix = pattern[star_idx+1:end]
    if isempty(prefix)
        return endswith(changed_file, suffix)
    elseif isempty(suffix)
        return startswith(changed_file, prefix)
    else
        return startswith(changed_file, prefix) && endswith(changed_file, suffix)
    end
end

"""
    must_run_tags(rules::Vector{MustRunRule}, changed_files::Vector{String}) -> Vector{Symbol}

Given a list of must-run rules and changed files, return the set of test tags
that should be force-selected (deduplicated).
"""
function must_run_tags(rules::Vector{MustRunRule}, changed_files::Vector{String})::Vector{Symbol}
    tags = Set{Symbol}()
    for rule in rules
        for file in changed_files
            if matches_must_run_rule(rule, file)
                push!(tags, rule.test_tag)
                break
            end
        end
    end
    return collect(tags)
end

"""
    parse_must_run_rules(config::Dict) -> Vector{MustRunRule}

Parse must-run rules from a config dict (as parsed from Testimonial.toml).

Expected schema:
```toml
[must_run]
rules = [
    { changed_glob = "src/critical/*.jl", test_tag = "critical" },
    { changed_glob = "config/*.toml", test_tag = "config" },
]
```

Returns an empty vector if the config has no must_run section or no rules.
Test_tag values are converted from strings to Symbols.
"""
function parse_must_run_rules(config::Dict)::Vector{MustRunRule}
    if !haskey(config, "must_run")
        return MustRunRule[]
    end
    must_run = config["must_run"]
    if !haskey(must_run, "rules") || !isa(must_run["rules"], Vector)
        return MustRunRule[]
    end
    rules_raw = must_run["rules"]
    rules = MustRunRule[]
    for r in rules_raw
        if isa(r, Dict) && haskey(r, "changed_glob") && haskey(r, "test_tag")
            tag = isa(r["test_tag"], Symbol) ? r["test_tag"] : Symbol(r["test_tag"])
            push!(rules, MustRunRule(String(r["changed_glob"]), tag))
        end
    end
    return rules
end

# ── Scoped fallback ─────────────────────────────

"""
    scoped_fallback(fallback_reasons::Vector{String}, component_mode::Symbol) -> Union{Nothing, Symbol}

Determine whether to fall back to a full suite run based on fallback reasons
and the current component mode.

Before component boundary is deployed (`:no_component_boundary`), any fallback
reason triggers a global full suite (`:full_suite`). After component boundary
(`:per_component`), only the affected component falls back.

Returns `nothing` if no fallback is needed.
Accepts `fallback_reasons` from `collect_fallback_reasons`.
"""
function scoped_fallback(fallback_reasons::Vector{String}, component_mode::Symbol=:no_component_boundary)::Union{Nothing, Symbol}
    isempty(fallback_reasons) && return nothing
    # Before component boundary: any fallback = global full suite
    return :full_suite
end

"""
    collect_fallback_reasons(results::Vector{ImpactResult}) -> Vector{String}

Collect non-nothing fallback_reason values from a vector of ImpactResults.
Returns only reasons that are set (not nothing).
"""
function collect_fallback_reasons(results::Vector{ImpactResult})::Vector{String}
    reasons = String[]
    for r in results
        if r.fallback_reason !== nothing
            push!(reasons, r.fallback_reason)
        end
    end
    return reasons
end

"""
    must_run_with_fallback_priority(rules, changed_files, fallback_reasons) -> Union{Nothing, Symbol}

Determine whether must-run rules should be applied or fallback takes priority.

Returns:
- `:must_run` — apply must-run rules (no fallback, rules match changed files)
- `:fallback` — fallback takes priority, suppress must-run
- `nothing` — neither applies (no rules matched, no fallback)

Priority: fallback > must-run. If any fallback reason exists, the suite
falls back and must-run rules are not needed.
"""
function must_run_with_fallback_priority(
    rules::Vector{MustRunRule},
    changed_files::Vector{String},
    fallback_reasons::Vector{String},
)::Union{Nothing, Symbol}
    # Fallback always wins
    if !isempty(fallback_reasons)
        return :fallback
    end

    # Check if any rules match changed files
    for rule in rules
        for file in changed_files
            if matches_must_run_rule(rule, file)
                return :must_run
            end
        end
    end

    return nothing
end

# ── Seeded fault test patterns ──────────────────

"""
Seed patterns for the seeded fault recall test. Each pattern describes a
fault to inject into the repo and the test that should be selected.

Covers common cases:
1. New function added to a source file
2. Modified function body in a source file
3. New file added to src/
4. Deleted file from src/
5. Multiple files changed
"""
const SEED_FAULT_PATTERNS = [
    (
        name = "new-function",
        description = "Add a new function to an existing source file",
        action = "Append a new function definition to a .jl file in src/",
        revealing_test = "A test that calls the new function should be selected",
    ),
    (
        name = "modified-function",
        description = "Modify the body of an existing function",
        action = "Change the implementation of a function in a .jl file in src/",
        revealing_test = "A test that exercises the changed function should be selected",
    ),
    (
        name = "new-file",
        description = "Add a new source file to the project",
        action = "Create a new .jl file in src/ with function definitions",
        revealing_test = "A test that imports from the new file should be selected",
    ),
    (
        name = "deleted-file",
        description = "Delete an existing source file from the project",
        action = "Remove a .jl file from src/",
        revealing_test = "All tests that covered the deleted file should be selected",
    ),
    (
        name = "multiple-files",
        description = "Modify multiple source files across different packages",
        action = "Change functions in two or more .jl files in src/",
        revealing_test = "Tests that cover any of the modified files should be selected",
    ),
]

# ── Seeded fault test verification ─────────────

"""
    run_seeded_fault_test(pattern) -> NamedTuple

Validate a single seed pattern structure and return results.

Returns a NamedTuple with fields:
- `pattern_name` — name of the pattern
- `passed` — whether validation succeeded
- `selected_items` — number of items selected (or 0 on error)
- `error` — error message if the pattern is invalid

!!! note "Placeholder"
    This function validates the pattern structure but does not perform
    actual mutation. The real fault injection and selection verification
    is performed by `scripts/seeded_fault_test.jl`. See Decision 7 in
    the add-safety-invariants design document.
"""
function run_seeded_fault_test(pattern)::NamedTuple
    if !haskey(pattern, :name) || !haskey(pattern, :action) ||
       !haskey(pattern, :revealing_test) ||
       isempty(get(pattern, :action, "")) ||
       isempty(get(pattern, :revealing_test, ""))
        return (
            pattern_name = get(pattern, :name, "unknown"),
            passed = false,
            selected_items = 0,
            error = "Invalid pattern: missing or empty required fields",
        )
    end

    @warn "Placeholder: no actual mutation is performed by run_seeded_fault_test. " *
          "Use scripts/seeded_fault_test.jl for real mutation testing." maxlog=1

    return (
        pattern_name = pattern.name,
        passed = true,
        selected_items = 1,
        error = "",
    )
end

"""
    run_all_seeded_fault_tests() -> Vector{NamedTuple}

Run all seeded fault patterns and return results.
Equivalent to calling `run_seeded_fault_test` for each pattern
in `SEED_FAULT_PATTERNS`.
"""
function run_all_seeded_fault_tests()::Vector{NamedTuple}
    return [run_seeded_fault_test(p) for p in SEED_FAULT_PATTERNS]
end

# ── TOML config ─────────────────────────────────

"""
    read_testimonial_config(project_dir::String) -> Dict{String, Any}

Read the Testimonial.toml configuration file from the project directory.

Returns an empty Dict if the file doesn't exist or cannot be parsed.
"""
function read_testimonial_config(project_dir::String)::Dict{String, Any}
    config_path = joinpath(project_dir, "Testimonial.toml")
    if !isfile(config_path)
        return Dict{String, Any}()
    end
    try
        return TOML.parsefile(config_path)
    catch
        @warn "Failed to parse Testimonial.toml at $config_path"
        return Dict{String, Any}()
    end
end

"""
    parse_components_override(config::Dict) -> Dict{Symbol, String}

Parse the `[components]` section from a Testimonial.toml config dict.

Expected format:
```toml
[components]
PkgA = "pkgs/PkgA"
PkgB = "pkgs/PkgB"
```

Each key-value pair maps a component name (Symbol) to its workspace
directory path (relative to the project root).

Returns an empty Dict if no `[components]` section exists or the section
is empty.
"""
function parse_components_override(config::Dict{String, Any})::Dict{Symbol, String}
    if !haskey(config, "components") || !isa(config["components"], Dict)
        return Dict{Symbol, String}()
    end
    components = config["components"]
    path_map = Dict{Symbol, String}()
    for (name, path) in components
        push!(path_map, Symbol(name) => String(path))
    end
    return path_map
end

"""
    parse_safety_mode(config::Dict) -> Symbol

Parse the `[safety]` section from a Testimonial.toml config dict.

Expected format:
```toml
[safety]
mode = "shadow"    # or "enforcing"
```

Returns `:shadow` if mode is "shadow", `:enforcing` if mode is "enforcing".
Returns `:shadow` as the safe default if the key is missing or invalid.
"""
function parse_safety_mode(config::Dict)::Symbol
    if !haskey(config, "safety") || !isa(config["safety"], Dict)
        return :shadow
    end
    safety = config["safety"]
    mode = get(safety, "mode", "shadow")
    if mode == "enforcing"
        return :enforcing
    end
    return :shadow
end

# ── Component discovery ─────────────────────────

"""
    discover_components(project_dir::String) -> Vector{Symbol}

Discover component names from a workspace Project.toml.

If the Project.toml has a `[workspace]` section with `packages`, each
package's own Project.toml is read to get the component name (the `name`
field). If no workspace section exists, the top-level package name is
returned as a single component.

Returns an empty vector if no Project.toml exists.
"""
function discover_components(project_dir::String)::Vector{Symbol}
    proj_path = joinpath(project_dir, "Project.toml")
    if !isfile(proj_path)
        return Symbol[]
    end

    content = read(proj_path, String)

    # Extract workspace packages if present
    workspace_match = match(r"\[workspace\]\s*\n(.*?)(?:\n\[|\z)"s, content)

    if workspace_match !== nothing
        ws_section = workspace_match.captures[1]
        # Extract packages = [...] line
        pkgs_match = match(r"packages\s*=\s*\[(.*?)\]", ws_section)
        if pkgs_match !== nothing
            pkg_str = pkgs_match.captures[1]
            # Parse package paths (could be strings or symbols)
            pkg_paths = [strip(p, ['\"', '\'', ' ']) for p in split(pkg_str, ",")]
            pkg_paths = filter(!isempty, pkg_paths)

            if isempty(pkg_paths)
                # Empty workspace — use top-level package name
                name_match = match(r"^name\s*=\s*\"([^\"]+)\""m, content)
                if name_match !== nothing
                    return [Symbol(name_match.captures[1])]
                end
                return Symbol[]
            end

            components = Symbol[]
            for pkg_path in pkg_paths
                abs_pkg = isabspath(pkg_path) ? pkg_path : joinpath(project_dir, pkg_path)
                pkg_proj = joinpath(abs_pkg, "Project.toml")
                if isfile(pkg_proj)
                    pkg_content = read(pkg_proj, String)
                    name_match = match(r"^name\s*=\s*\"([^\"]+)\""m, pkg_content)
                    if name_match !== nothing
                        push!(components, Symbol(name_match.captures[1]))
                    end
                end
            end

            return isempty(components) ? Symbol[] : components
        end
    end

    # No workspace section — use top-level package name
    name_match = match(r"^name\s*=\s*\"([^\"]+)\""m, content)
    if name_match !== nothing
        return [Symbol(name_match.captures[1])]
    end

    return Symbol[]
end

"""
    component_of(test_file::String, components::Vector{Symbol}) -> Union{Symbol, Nothing}

Determine which component a test file belongs to.

Checks if the file path contains a component name as a directory segment.
Returns the first matching component, or `nothing` if no match is found.
"""
function component_of(test_file::String, components::Vector{Symbol})::Union{Symbol, Nothing}
    for comp in components
        comp_str = string(comp)
        if occursin("/$(comp_str)/", test_file) || occursin("$(comp_str)\\test", test_file)
            return comp
        end
    end
    return nothing
end

"""
    component_paths(project_dir::String) -> Dict{Symbol, String}

Discover component names and their workspace directory paths from a workspace
Project.toml.

Returns a dict mapping each component name (Symbol) to its absolute workspace
directory path. Works the same as `discover_components` but preserves the
path information for proper file-to-component mapping.

If the Project.toml has a `[workspace]` section with `packages`, each
package's workspace path is resolved. If no workspace section exists, the
top-level package name is mapped to the project directory itself.

Returns an empty dict if no Project.toml exists.
"""
function component_paths(project_dir::String)::Dict{Symbol, String}
    # Check Testimonial.toml for components override first
    config = read_testimonial_config(project_dir)
    if haskey(config, "components") && !isempty(config["components"])
        raw = parse_components_override(config)
        # Resolve relative paths against project_dir
        path_map = Dict{Symbol, String}()
        for (comp, rel_path) in raw
            abs_path = isabspath(rel_path) ? rel_path : joinpath(project_dir, rel_path)
            path_map[comp] = abs_path
        end
        return path_map
    end

    proj_path = joinpath(project_dir, "Project.toml")
    if !isfile(proj_path)
        return Dict{Symbol, String}()
    end

    content = read(proj_path, String)

    # Extract workspace packages if present
    workspace_match = match(r"\[workspace\]\s*\n(.*?)(?:\n\[|\z)"s, content)

    if workspace_match !== nothing
        ws_section = workspace_match.captures[1]
        # Extract packages = [...] line
        pkgs_match = match(r"packages\s*=\s*\[(.*?)\]", ws_section)
        if pkgs_match !== nothing
            pkg_str = pkgs_match.captures[1]
            # Parse package paths (could be strings or symbols)
            pkg_paths = [strip(p, ['"', '\'', ' ']) for p in split(pkg_str, ",")]
            pkg_paths = filter(!isempty, pkg_paths)

            if isempty(pkg_paths)
                # Empty workspace — use top-level package name
                name_match = match(r"^name\s*=\s*\"([^\"]+)\""m, content)
                if name_match !== nothing
                    return Dict{Symbol, String}(
                        Symbol(name_match.captures[1]) => project_dir
                    )
                end
                return Dict{Symbol, String}()
            end

            path_map = Dict{Symbol, String}()
            for pkg_path in pkg_paths
                abs_pkg = isabspath(pkg_path) ? pkg_path : joinpath(project_dir, pkg_path)
                pkg_proj = joinpath(abs_pkg, "Project.toml")
                if isfile(pkg_proj)
                    pkg_content = read(pkg_proj, String)
                    name_match = match(r"^name\s*=\s*\"([^\"]+)\""m, pkg_content)
                    if name_match !== nothing
                        path_map[Symbol(name_match.captures[1])] = abs_pkg
                    end
                end
            end

            return path_map
        end
    end

    # No workspace section — use top-level package name
    name_match = match(r"^name\s*=\s*\"([^\"]+)\""m, content)
    if name_match !== nothing
        return Dict{Symbol, String}(
            Symbol(name_match.captures[1]) => project_dir
        )
    end

    return Dict{Symbol, String}()
end

"""
    component_of(test_file::String, path_map::Dict{Symbol, String}) -> Union{Symbol, Nothing}

Determine which component a test file belongs to, using workspace path
prefix matching.

Checks if the test file path starts with any component's workspace
directory path. This is more robust than the name-based `component_of`
because it works regardless of whether the component name matches the
workspace directory name.

Returns the first matching component, or `nothing` if no match is found.
"""
function component_of(test_file::String, path_map::Dict{Symbol, String})::Union{Symbol, Nothing}
    for (comp, ws_path) in path_map
        # Normalize both paths for comparison
        norm_file = replace(test_file, '\\' => '/')
        norm_ws = replace(ws_path, '\\' => '/')
        if startswith(norm_file, norm_ws)
            return comp
        end
    end
    return nothing
end

"""In-memory store mapping (file, name) → consecutive pass count.

Note: This is per-process state. Counters reset when the Julia process restarts.
For cross-session persistence, this should be written to .testimonial/run_history.jls
(see add-runtime-feedback epic).
"""
const _ALWAYS_RUN_PASS_COUNTS = Dict{Tuple{String, String}, Int}()

"""
    consecutive_passes(ref) -> Int

Get the number of consecutive passing runs for a test item.
Returns 0 for tests with no recorded history.
"""
function consecutive_passes(ref::TestItemRef)::Int
    return get(_ALWAYS_RUN_PASS_COUNTS, (ref.file, ref.name), 0)
end

"""
    record_run(ref, passed::Bool; threshold=DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD)

Record a run outcome for a test item.
- If `passed` is true, increment the consecutive pass counter.
- If `passed` is false, reset the counter to 0.
"""
function record_run(ref::TestItemRef, passed::Bool; threshold::Int=DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD)
    key = (ref.file, ref.name)
    if passed
        _ALWAYS_RUN_PASS_COUNTS[key] = get(_ALWAYS_RUN_PASS_COUNTS, key, 0) + 1
    else
        _ALWAYS_RUN_PASS_COUNTS[key] = 0
    end
    return nothing
end

"""
    should_evict(ref; threshold=DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD) -> Bool

Check whether a test item should be removed from the always-run set.
Returns true if consecutive passes >= threshold.
"""
function should_evict(ref::TestItemRef; threshold::Int=DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD)::Bool
    return consecutive_passes(ref) >= threshold
end

"""
    reset_always_run_state(ref)

Reset the always-run pass counter for a test item to 0.
"""
function reset_always_run_state(ref::TestItemRef)
    delete!(_ALWAYS_RUN_PASS_COUNTS, (ref.file, ref.name))
    return nothing
end

"""
    get_always_run_tests(; threshold=DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD) -> Vector{Tuple{String, String}}

Return the list of `(file, name)` test pairs currently in the always-run
set — tests with consecutive pass counts below the eviction threshold.

These tests failed recently (or have no history) and should be included
in every run regardless of the coverage-based selection.
"""
function get_always_run_tests(; threshold::Int=DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD)::Vector{Tuple{String, String}}
    always_run = Tuple{String, String}[]
    for (key, passes) in _ALWAYS_RUN_PASS_COUNTS
        if passes < threshold
            push!(always_run, key)
        end
    end
    return always_run
end

# ── Run history (duration tracking for shard balancing) ───────

"""Default path for the run history persistence file."""
const DEFAULT_RUN_HISTORY_PATH = ".testimonial/run_history.jls"

"""Per-test execution outcomes and timing for runtime feedback.

Tracks pass/fail outcomes, duration, and timing for the runtime feedback
pipeline (FEED-003). Persisted independently from CoverageIndex to survive
index rebuilds.

# Fields
- `outcomes::Vector{Bool}`: chronological pass (true) / fail (false) outcomes
- `attempt_count::Int`: total attempts recorded
- `failure_rate::Float64`: proportion of attempts that failed
- `first_seen::DateTime`: first recorded outcome
- `last_seen::DateTime`: most recent recorded outcome
"""
struct RunHistoryEntry
    outcomes :: Vector{Bool}
    attempt_count :: Int
    failure_rate :: Float64
    first_seen :: DateTime
    last_seen :: DateTime
end

"""A single entry in the run history."""
struct RunEntry
    mean_duration :: Float64
    count :: Int
    last_duration :: Float64
end

"""
    RunHistory

Collects per-test execution durations for shard balancing and per-test
outcome/timing data for runtime feedback.

Persisted to `.testimonial/run_history.jls` for cross-session tracking.
See openspec/changes/add-component-boundary/design.md Decision 4.
"""
struct RunHistory
    entries :: Dict{Tuple{String, String}, RunEntry}
    outcome_entries :: Dict{Tuple{String, String}, RunHistoryEntry}
end

# Convenience constructors
RunHistory() = RunHistory(Dict{Tuple{String, String}, RunEntry}(), Dict{Tuple{String, String}, RunHistoryEntry}())

# Backward-compatible constructor for deserialization of old format (no outcome_entries)
RunHistory(entries::Dict{Tuple{String, String}, RunEntry}) =
    RunHistory(entries, Dict{Tuple{String, String}, RunHistoryEntry}())

"""
    record_duration!(history::RunHistory, ref::TestItemRef, duration::Float64)

Record a test execution duration in the run history.

Updates the running mean duration, increments the count, and stores the
most recent duration. The running mean is computed as:
    new_mean = old_mean + (duration - old_mean) / count

This is an online algorithm (O(1) memory, no sum overflow) suitable for
streaming updates.
"""
function record_duration!(history::RunHistory, ref::TestItemRef, duration::Float64)
    key = (ref.file, ref.name)
    if haskey(history.entries, key)
        entry = history.entries[key]
        new_count = entry.count + 1
        new_mean = entry.mean_duration + (duration - entry.mean_duration) / new_count
        history.entries[key] = RunEntry(new_mean, new_count, duration)
    else
        history.entries[key] = RunEntry(duration, 1, duration)
    end
    return nothing
end

"""
    read_durations(history::RunHistory) -> Dict{Tuple{String, String}, Float64}

Read per-test mean durations from the run history.

Returns a dict mapping each test item (identified by file, name) to its
recorded mean duration in seconds. This is the data used by the shard
balancing algorithm (see testimonial-13f).

Returns an empty dict if the history is empty.
"""
function read_durations(history::RunHistory)::Dict{Tuple{String, String}, Float64}
    result = Dict{Tuple{String, String}, Float64}()
    for (key, entry) in history.entries
        result[key] = entry.mean_duration
    end
    return result
end

"""
    record_outcome_history!(history::RunHistory, ref::TestItemRef, entry::RunHistoryEntry)

Record a test execution outcome entry in the run history.

Replaces any existing outcome entry for the same test. Callers should
merge cumulative data (outcomes, failure_rate) before calling.
"""
function record_outcome_history!(history::RunHistory, ref::TestItemRef, entry::RunHistoryEntry)
    key = (ref.file, ref.name)
    history.outcome_entries[key] = entry
    return nothing
end

"""
    get_outcome_history(history::RunHistory, ref::TestItemRef) -> Union{RunHistoryEntry, Nothing}

Retrieve the outcome history for a specific test.

Returns the `RunHistoryEntry` if one exists, or `nothing` if the test
has no recorded outcome history.
"""
function get_outcome_history(history::RunHistory, ref::TestItemRef)::Union{RunHistoryEntry, Nothing}
    key = (ref.file, ref.name)
    return get(history.outcome_entries, key, nothing)
end

"""
    save_run_history(history::RunHistory, path::String=DEFAULT_RUN_HISTORY_PATH)

Persist the run history to disk via serialization.

Creates parent directories if needed and writes atomically via
temp-file + rename.
"""
function save_run_history(history::RunHistory, path::String=DEFAULT_RUN_HISTORY_PATH)
    dir = dirname(path)
    mkpath(dir)
    tmppath = path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, history)
    end
    mv(tmppath, path; force=true)
    return nothing
end

"""
    load_run_history(path::String=DEFAULT_RUN_HISTORY_PATH) -> RunHistory

Load a persisted run history from disk.

Returns an empty `RunHistory` if the file doesn't exist, can't be read,
or fails deserialization.
"""
function load_run_history(path::String=DEFAULT_RUN_HISTORY_PATH)::RunHistory
    if !isfile(path)
        return RunHistory()
    end
    try
        result = open(deserialize, path, "r")
        if result isa RunHistory
            return result
        end
        return RunHistory()
    catch
        return RunHistory()
    end
end

# ── Ingest (runtime feedback pipeline) ─────────────────

"""Default path for tracking ingested run keys (idempotency)."""
const INGESTED_RUNS_PATH = ".testimonial/ingested_runs.jls"

"""
    save_ingested_run_key(run_key::String, timestamp::DateTime=now(), path::String=INGESTED_RUNS_PATH)

Record a run key as already ingested (for idempotency), with its timestamp.

Persists to `.testimonial/ingested_runs.jls` atomically, storing a
`Dict{String, DateTime}` mapping keys to ingestion timestamps.
"""
function save_ingested_run_key(run_key::String, timestamp::DateTime=now(), path::String=INGESTED_RUNS_PATH)
    keys = load_ingested_run_keys(path)
    keys[run_key] = timestamp
    dir = dirname(path)
    mkpath(dir)
    tmppath = path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, keys)
    end
    mv(tmppath, path; force=true)
    return nothing
end

"""
    load_ingested_run_keys(path::String=INGESTED_RUNS_PATH) -> Dict{String, DateTime}

Load the dict of ingested run keys to their timestamps.

Returns an empty dict if no ingestion history exists.
Backward-compatible: old `Set{String}` files are converted on read.
"""
function load_ingested_run_keys(path::String=INGESTED_RUNS_PATH)::Dict{String, DateTime}
    if !isfile(path)
        return Dict{String, DateTime}()
    end
    try
        result = open(deserialize, path, "r")
        if result isa Dict{String, DateTime}
            return result
        end
        # Backward compatibility: old Set{String} format
        if result isa Set{String}
            now_ts = now()
            return Dict(k => now_ts for k in result)
        end
        return Dict{String, DateTime}()
    catch
        return Dict{String, DateTime}()
    end
end

"""
    prune_ingested_run_keys(max_age_days::Int=30, path::String=INGESTED_RUNS_PATH) -> Int

Remove ingested run keys older than `max_age_days`.

Returns the number of keys pruned.
"""
function prune_ingested_run_keys(max_age_days::Int=30, path::String=INGESTED_RUNS_PATH)::Int
    keys = load_ingested_run_keys(path)
    isempty(keys) && return 0

    cutoff = now() - Day(max_age_days)
    to_prune = [k for (k, ts) in keys if ts < cutoff]

    if isempty(to_prune)
        return 0
    end

    for k in to_prune
        delete!(keys, k)
    end

    dir = dirname(path)
    mkpath(dir)
    tmppath = path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, keys)
    end
    mv(tmppath, path; force=true)

    return length(to_prune)
end

"""
    ingest(; run_key::String,
             index_path::String=".testimonial/index.jls",
             passed_items::Vector{TestItemRef}=TestItemRef[],
             failed_items::Vector{TestItemRef}=TestItemRef[],
             test_dirs::Vector{String}=String["test/"]) -> NamedTuple

Post-run coverage and outcome ingestion pipeline.

Parses coverage sidecar files from the last test run, computes new
runtime edges (file, line pairs exercised at runtime but not previously
recorded), updates the index, persists run history, and enforces
idempotent ingestion via run-key deduplication.

# Arguments
- `run_key::String`: unique identifier for this run (required). Used for
  idempotency — the same key rejected on subsequent calls.
- `index_path::String`: path to the CoverageIndex on disk
- `passed_items::Vector{TestItemRef}`: test items that passed (for run history)
- `failed_items::Vector{TestItemRef}`: test items that failed (for run history)
- `test_dirs::Vector{String}`: directories to scan for test items

# Returns
NamedTuple with fields:
- `runtime_edges_created::Int`: number of new runtime edges recorded
- `items_ingested::Int`: number of test items processed
- `duplicate_skipped::Bool`: true if run_key was already ingested
"""
function ingest(;
    run_key::String,
    index_path::String=".testimonial/index.jls",
    passed_items::Vector{TestItemRef}=TestItemRef[],
    failed_items::Vector{TestItemRef}=TestItemRef[],
    test_dirs::Vector{String}=String["test/"],
)::NamedTuple
    # Step 1: Check idempotency
    ingested = load_ingested_run_keys()
    if haskey(ingested, run_key)
        @info "Ingest: run_key '$run_key' already ingested, skipping (FEED-004)"
        return (
            runtime_edges_created = 0,
            items_ingested = 0,
            duplicate_skipped = true,
        )
    end

    # Step 2: Load the index
    index = load_index(index_path)
    if index === nothing
        @warn "Ingest: no coverage index at $index_path, recording run key only"
        save_ingested_run_key(run_key)
        return (
            runtime_edges_created = 0,
            items_ingested = 0,
            duplicate_skipped = false,
        )
    end

    # Step 3: Discover test items to find all known items
    discovered = discover_testitems(test_dirs)
    total_items = length(discovered)

    # Step 4: Parse coverage sidecar files
    # After a Julia test run with --code-coverage=user, .jl.cov sidecar
    # files exist next to source files. Parse them to find covered lines.
    new_edges = Dict{TestItemRef, Vector{Tuple{String, Int}}}()
    items_processed = 0

    # Collect all .jl.cov files in the workspace
    cov_files = _find_cov_files()

    for (ref, ic) in index.items
        items_processed += 1

        # Check existing source_files for NEW coverage
        for (src_file, (covered, _uncovered)) in ic.source_files
            cov_path = src_file * ".cov"
            if !isfile(cov_path)
                continue
            end

            # Parse the sidecar to get covered lines from this run
            covered_set = Set(cov_lines(cov_path))
            existing_set = Set(covered)

            new_lines = setdiff(covered_set, existing_set)
            for line in new_lines
                if !haskey(new_edges, ref)
                    new_edges[ref] = Vector{Tuple{String, Int}}()
                end
                push!(new_edges[ref], (src_file, line))
            end
        end

        # Also check test file's own coverage sidecar
        test_cov_path = ref.file * ".cov"
        if isfile(test_cov_path)
            test_covered = Set(cov_lines(test_cov_path))

            # Check if the test file coverage is already in source_files
            test_file_covered = get(ic.source_files, ref.file, (Int[], Int[]))[1]
            existing_test_covered = Set(test_file_covered)
            new_test_lines = setdiff(test_covered, existing_test_covered)

            for line in new_test_lines
                if !haskey(new_edges, ref)
                    new_edges[ref] = Vector{Tuple{String, Int}}()
                end
                push!(new_edges[ref], (ref.file, line))
            end
        end

        # Check all cov files that aren't in source_files
        for cov_path in cov_files
            src_file = cov_path[1:end-4]  # remove .cov suffix
            if haskey(ic.source_files, src_file)
                continue  # already checked above
            end
            if src_file == ref.file
                continue  # already checked above
            end

            # Check if this source file is in the project
            if !isfile(src_file)
                continue
            end

            covered = cov_lines(cov_path)
            if !isempty(covered)
                # This is a NEW source file for this test — runtime edge
                if !haskey(new_edges, ref)
                    new_edges[ref] = Vector{Tuple{String, Int}}()
                end
                for line in covered
                    push!(new_edges[ref], (src_file, line))
                end
            end
        end
    end

    # Step 5: Store new runtime edges in the index
    total_new_edges = 0
    if !isempty(new_edges)
        # Merge new edges into existing runtime_edges
        merged = copy(index.runtime_edges)
        for (ref, edges) in new_edges
            if haskey(merged, ref)
                existing_edges = Set(merged[ref])
                for e in edges
                    if e ∉ existing_edges
                        push!(merged[ref], e)
                        total_new_edges += 1
                    end
                end
            else
                merged[ref] = edges
                total_new_edges += length(edges)
            end
        end

        # Update index with new runtime_edges
        updated_index = CoverageIndex(
            index.items,
            index.git_hash,
            index.julia_version,
            index.schema_version,
            index.created_at,
            index.environment_fingerprint,
            index.inter_component_edges,
            merged,
            index,  # preserve metadata fields
        )
        save_index(updated_index, index_path)
    end

    # Step 6: Update run history
    all_items = vcat(passed_items, failed_items)
    if !isempty(all_items)
        history = load_run_history()
        for ref in all_items
            # Determine if this test passed or failed
            passed = ref in passed_items
            existing = get_outcome_history(history, ref)
            if existing !== nothing
                new_outcomes = vcat(existing.outcomes, [passed])
                new_count = existing.attempt_count + 1
                new_failure_rate = count(!, new_outcomes) / new_count
                updated_entry = RunHistoryEntry(
                    new_outcomes,
                    new_count,
                    new_failure_rate,
                    existing.first_seen,
                    now(),
                )
                record_outcome_history!(history, ref, updated_entry)
            else
                new_entry = RunHistoryEntry(
                    [passed],
                    1,
                    passed ? 0.0 : 1.0,
                    now(),
                    now(),
                )
                record_outcome_history!(history, ref, new_entry)
            end
        end
        save_run_history(history)
    end

    # Step 7: Record run key for idempotency
    save_ingested_run_key(run_key)

    return (
        runtime_edges_created = total_new_edges,
        items_ingested = items_processed,
        duplicate_skipped = false,
    )
end

"""
    _find_cov_files() -> Vector{String}

Scan the workspace for .jl.cov coverage sidecar files.

Looks in the current directory (recursively) for files matching *.jl.cov.
These are created by Julia when running with --code-coverage=user.
"""
function _find_cov_files()::Vector{String}
    cov_files = String[]
    for (root, dirs, files) in walkdir(".")
        for f in files
            if endswith(f, ".jl.cov")
                path = joinpath(root, f)
                # Normalize to strip ./ prefix
                path = normpath(path)
                push!(cov_files, path)
            end
        end
    end
    return cov_files
end

"""
    cov_lines(cov_path::AbstractString) -> Vector{Int}

Parse a Julia .jl.cov coverage sidecar file and return the line numbers
that have positive execution counts. Lines with count > 0 are considered
covered.
"""
function cov_lines(cov_path::AbstractString)::Vector{Int}
    result = Int[]
    if !isfile(cov_path)
        return result
    end
    for line in eachline(cov_path)
        # Format: "<count>: <linenum>: <source>" possibly with leading whitespace
        # Lines with count > 0 are covered; "-" means not executable
        m = match(r"^\s*(\d+):\s*(\d+):", line)
        if m !== nothing
            count = parse(Int, m[1])
            linenum = parse(Int, m[2])
            if count > 0
                push!(result, linenum)
            end
        end
    end
    return result
end

# ════════════════════════════════════════════
# 6. Provenance persistence
# ════════════════════════════════════════════

"""Default directory for provenance storage."""
const DEFAULT_PROVENANCE_DIR = ".testimonial/provenance/"

"""
    provenance_path(run_key, dir=DEFAULT_PROVENANCE_DIR) -> String

Get the file path for a run key's provenance data.
"""
function provenance_path(run_key::String, dir::String=DEFAULT_PROVENANCE_DIR)::String
    return joinpath(dir, string(run_key, ".jls"))
end

"""
    save_provenance(run_key, results, dir=DEFAULT_PROVENANCE_DIR)

Store provenance (selection results) for a smart_run run key.

Persists `Vector{ImpactResult}` to `.testimonial/provenance/<run_key>.jls`
using atomic write (temp file + rename). Creates parent directories as
needed.
"""
function save_provenance(run_key::String, results::Vector{ImpactResult}, dir::String=DEFAULT_PROVENANCE_DIR)
    path = provenance_path(run_key, dir)
    parent = dirname(path)
    mkpath(parent)
    tmppath = path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, results)
    end
    mv(tmppath, path; force=true)
    return nothing
end

"""
    load_provenance(run_key, dir=DEFAULT_PROVENANCE_DIR) -> Vector{ImpactResult}

Load persisted provenance data for a run key.

Returns the `Vector{ImpactResult}` if the file exists, or an empty
vector if the file is missing, corrupt, or fails deserialization.
"""
function load_provenance(run_key::String, dir::String=DEFAULT_PROVENANCE_DIR)::Vector{ImpactResult}
    path = provenance_path(run_key, dir)
    if !isfile(path)
        return ImpactResult[]
    end
    try
        result = open(deserialize, path, "r")
        if result isa Vector{ImpactResult}
            return result
        end
        return ImpactResult[]
    catch
        return ImpactResult[]
    end
end

export DEFAULT_PROVENANCE_DIR, provenance_path, save_provenance, load_provenance

# ── Incident persistence ──────────────────────────

"""Default path for incident storage."""
const INCIDENTS_PATH = joinpath(".testimonial", "incidents.jls")

"""
    save_incidents(incidents::Vector{MissedSelectionIncident}, path::String=INCIDENTS_PATH)

Persist a vector of missed-selection incidents to disk.
Uses atomic write (tmp + rename).
"""
function save_incidents(incidents::Vector{MissedSelectionIncident}, path::String=INCIDENTS_PATH)
    dir = dirname(path)
    mkpath(dir)
    tmppath = path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, incidents)
    end
    mv(tmppath, path; force=true)
    return nothing
end

"""
    load_incidents(path::String=INCIDENTS_PATH) -> Vector{MissedSelectionIncident}

Load persisted incidents from disk.
Returns an empty vector if the file doesn't exist, can't be read,
or fails deserialization.
"""
function load_incidents(path::String=INCIDENTS_PATH)::Vector{MissedSelectionIncident}
    if !isfile(path)
        return MissedSelectionIncident[]
    end
    try
        result = open(deserialize, path, "r")
        if result isa Vector{MissedSelectionIncident}
            return result
        end
        return MissedSelectionIncident[]
    catch
        return MissedSelectionIncident[]
    end
end

"""
    append_incident(incident::MissedSelectionIncident, path::String=INCIDENTS_PATH)

Load existing incidents, append a new one, and save.
If the file doesn't exist, starts with an empty list.
"""
function append_incident(incident::MissedSelectionIncident, path::String=INCIDENTS_PATH)
    existing = load_incidents(path)
    push!(existing, incident)
    save_incidents(existing, path)
    return nothing
end

"""
    compare_selection_vs_outcomes(selected, all_items, failed_items, changed_content) -> Vector{MissedSelectionIncident}

Compare the selected test set against full-run outcomes and return
candidate missed-selection incidents.

A candidate incident is recorded for each item that failed in the full
run but was NOT in the selected set. Items that failed but were selected
are not considered incidents (the selection worked correctly).

# Arguments
- `selected::Vector{TestItemRef}`: items that the selection algorithm picked
- `all_items::Vector{TestItemRef}`: all items that ran in the full suite
- `failed_items::Vector{TestItemRef}`: items that failed
- `changed_content::String`: the content unit (file path) that was changed
- `exclude::Set{Tuple{String, String}}=Set{Tuple{String, String}()}``: tests to exclude
  from incident detection (e.g., quarantined flaky tests)
"""
function compare_selection_vs_outcomes(
    selected::Vector{TestItemRef},
    all_items::Vector{TestItemRef},
    failed_items::Vector{TestItemRef},
    changed_content::String;
    exclude::Set{Tuple{String, String}}=Set{Tuple{String, String}}(),
)::Vector{MissedSelectionIncident}
    isempty(all_items) && return MissedSelectionIncident[]
    isempty(failed_items) && return MissedSelectionIncident[]

    # Build a set of selected items for O(1) lookup
    selected_set = Set(selected)

    incidents = MissedSelectionIncident[]
    now_ts = now()

    for failed in failed_items
        if failed ∉ selected_set && (failed.file, failed.name) ∉ exclude
            push!(incidents, MissedSelectionIncident(
                changed_content,
                failed,
                now_ts,
                Candidate,
            ))
        end
    end

    return incidents
end

"""
    promote_incidents(incidents, threshold=3) -> Vector{MissedSelectionIncident}

Promote candidate incidents to promoted status when the same
(changed_content, missed_test) pair appears at least `threshold` times.

Returns a new vector with updated statuses. Incidents below the
threshold are returned unchanged.

See SAFE-005 (incident promotion after confirmation) in the safety
invariants spec.

When `max_age_days` > 0, only incidents within the last N days are
counted toward the promotion threshold. Older incidents are returned
unchanged (not promoted, not demoted). This implements a rolling
evaluation window that prevents stale observations from triggering
premature promotion.
"""
function promote_incidents(
    incidents::Vector{MissedSelectionIncident},
    threshold::Int=3;
    max_age_days::Int=0,
)::Vector{MissedSelectionIncident}
    isempty(incidents) && return incidents

    # Filter to in-window incidents for counting
    cutoff = max_age_days > 0 ? now() - Dates.Day(max_age_days) : Dates.DateTime(0)

    # Count occurrences of each (changed_content, missed_test) pair
    counts = Dict{Tuple{String, String}, Int}()
    for inc in incidents
        key = (inc.changed_content, inc.missed_test.name)
        if max_age_days == 0 || inc.timestamp >= cutoff
            counts[key] = get(counts, key, 0) + 1
        end
    end

    # Build result: promote if count >= threshold
    result = MissedSelectionIncident[]
    for inc in incidents
        key = (inc.changed_content, inc.missed_test.name)
        new_status = get(counts, key, 0) >= threshold ? Promoted : inc.status
        push!(result, MissedSelectionIncident(
            inc.changed_content,
            inc.missed_test,
            inc.timestamp,
            new_status,
        ))
    end

    return result
end

"""
    reconcile(selected, all_items, failed_items, changed_content;
              promote_threshold=3, max_age_days=0) -> NamedTuple

Post-run reconciliation pipeline. Reconciliation is the process of
comparing the smart selection's predicted results against the actual
full-suite outcomes after a run completes. If the selection would have
missed a failing test, it's recorded as a candidate incident.

Pipeline:
1. Detect missed-selection incidents via compare_selection_vs_outcomes
2. Save new incidents
3. Promote qualifying incidents to manual edges (threshold-based)
4. Persist a timestamped report to .testimonial/reconciliation/

# Arguments
- `selected::Vector{TestItemRef}`: items that the selection algorithm picked
- `all_items::Vector{TestItemRef}`: all items that ran in the full suite
- `failed_items::Vector{TestItemRef}`: items that failed
- `changed_content::String`: the content unit (file) that was changed
- `promote_threshold::Int=3`: occurrences needed to promote (passed to promote_incidents)
- `max_age_days::Int=0`: evaluation window in days (0 = unlimited)

# Returns
NamedTuple with fields:
- `incidents_detected`: number of new candidate incidents recorded
- `incidents_promoted`: number of incidents promoted to Promoted status
- `manual_edges_created`: number of new manual edges created
- `total_incidents`: total incidents in storage after reconcile
- `total_manual_edges`: total manual edges in storage after reconcile
- `quarantined_excluded`: number of quarantined test failures excluded
"""
function reconcile(
    selected::Vector{TestItemRef},
    all_items::Vector{TestItemRef},
    failed_items::Vector{TestItemRef},
    changed_content::String;
    promote_threshold::Int=3,
    max_age_days::Int=0,
)::NamedTuple
    # Step 0: Load quarantined tests to exclude from incident detection
    quarantined = get_quarantined_tests()

    # Count quarantined failures that will be excluded
    quarantined_excluded = count(
        f -> (f.file, f.name) in quarantined, failed_items
    )

    # Step 1: Detect missed incidents (excluding quarantined/flaky tests)
    new_incidents = compare_selection_vs_outcomes(
        selected, all_items, failed_items, changed_content;
        exclude=quarantined,
    )

    # Step 2: Save new incidents
    for inc in new_incidents
        append_incident(inc)
    end

    # Step 3: Load all incidents and promote
    all_incidents = load_incidents()
    promoted = promote_incidents(all_incidents, promote_threshold; max_age_days=max_age_days)

    # Step 4: Save promoted incidents back
    save_incidents(promoted)

    # Step 5: Create manual edges from promoted incidents
    edges = create_manual_edges_from_promoted(promoted)

    # Step 6: Return report
    incidents_detected = length(new_incidents)
    incidents_promoted = count(i -> i.status == Promoted, promoted)
    total_incidents = length(promoted)
    total_manual_edges = length(edges)
    manual_edges_created = length(edges)  # create_manual_edges_from_promoted returns the full set
    ts = now()

    # Step 7: Persist reconciliation report
    report = (
        incidents_detected = incidents_detected,
        incidents_promoted = incidents_promoted,
        manual_edges_created = manual_edges_created,
        total_incidents = total_incidents,
        total_manual_edges = total_manual_edges,
        quarantined_excluded = quarantined_excluded,
        timestamp = ts,
    )
    _save_reconciliation_report(report)

    return report
end

"""
    _save_reconciliation_report(report::NamedTuple)

Save a reconciliation report to `.testimonial/reconciliation/` with a
timestamped filename.
"""
function _save_reconciliation_report(report::NamedTuple)::Nothing
    dir = joinpath(".testimonial", "reconciliation")
    mkpath(dir)
    ts_ms = Dates.value(Dates.now())
    # Handle edge case: multiple reports in same millisecond
    path = joinpath(dir, "reconciliation_$(ts_ms).jls")
    counter = 1
    while isfile(path)
        path = joinpath(dir, "reconciliation_$(ts_ms)_$(counter).jls")
        counter += 1
    end
    tmppath = path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, report)
    end
    mv(tmppath, path; force=true)
    return nothing
end

# ── Flaky detector ──────────────────────────────

"""Per-test outcome history: (file, name) → [pass1, pass2, ...]"""
const _OUTCOME_HISTORY = Dict{Tuple{String, String}, Vector{Bool}}()

"""Set of quarantined tests: Set{(file, name)}"""
const _QUARANTINED_TESTS = Set{Tuple{String, String}}()

"""
    record_outcome(ref::TestItemRef, passed::Bool)

Record a test outcome (pass/fail) for flaky detection.
"""
function record_outcome(ref::TestItemRef, passed::Bool)::Nothing
    key = (ref.file, ref.name)
    if !haskey(_OUTCOME_HISTORY, key)
        _OUTCOME_HISTORY[key] = Bool[]
    end
    push!(_OUTCOME_HISTORY[key], passed)
    return nothing
end

"""
    get_outcome_history(ref::TestItemRef) -> Vector{Bool}

Get the full outcome history for a test. Returns empty vector if no history.
"""
function get_outcome_history(ref::TestItemRef)::Vector{Bool}
    return get(_OUTCOME_HISTORY, (ref.file, ref.name), Bool[])
end

"""
    reset_flaky_history()

Clear all outcome history and quarantined flags. Used in testing.
"""
function reset_flaky_history()::Nothing
    empty!(_OUTCOME_HISTORY)
    empty!(_QUARANTINED_TESTS)
    return nothing
end

"""
    is_flaky(ref::TestItemRef; window::Int=5) -> Bool

Check if a test has inconsistent outcomes in its recent history.
A test is flaky if the last `window` outcomes contain both passes
and failures (at least one of each).
"""
function is_flaky(ref::TestItemRef; window::Int=5)::Bool
    history = get(_OUTCOME_HISTORY, (ref.file, ref.name), Bool[])
    isempty(history) && return false
    recent = history[max(1, end - window + 1):end]
    has_pass = any(recent)
    has_fail = any(!p for p in recent)
    return has_pass && has_fail
end

"""
    quarantine_test(ref::TestItemRef)

Mark a test as quarantined (flaky). Quarantined tests are excluded
from incident detection.
"""
function quarantine_test(ref::TestItemRef)::Nothing
    push!(_QUARANTINED_TESTS, (ref.file, ref.name))
    return nothing
end

"""
    unquarantine_test(ref::TestItemRef)

Remove a test from the quarantine list.
"""
function unquarantine_test(ref::TestItemRef)::Nothing
    delete!(_QUARANTINED_TESTS, (ref.file, ref.name))
    return nothing
end

"""
    get_quarantined_tests() -> Set{Tuple{String, String}}

Get the set of quarantined test keys.
"""
function get_quarantined_tests()::Set{Tuple{String, String}}
    return copy(_QUARANTINED_TESTS)
end

"""
    auto_quarantine_flaky(; window::Int=5) -> Set{Tuple{String, String}}

Scan all tests with outcome history and quarantine any that are flaky.
Returns the set of newly quarantined test keys.

A test is flaky if its recent history (last `window` outcomes) contains
both passes and failures.
"""
function auto_quarantine_flaky(; window::Int=5)::Set{Tuple{String, String}}
    newly_quarantined = Set{Tuple{String, String}}()
    keys_to_prune = Tuple{String, String}[]

    for (key, history) in _OUTCOME_HISTORY
        ref = TestItemRef(key[1], 0, key[2])

        if key ∉ _QUARANTINED_TESTS
            if is_flaky(ref; window=window)
                push!(_QUARANTINED_TESTS, key)
                push!(newly_quarantined, key)
            end
        end

        # Prune outcome histories for consistently-passing tests that
        # are not quarantined: if the last `window` outcomes are all
        # passes, the history is irrelevant for flaky detection.
        if key ∉ _QUARANTINED_TESTS && length(history) >= window
            recent = history[end - window + 1:end]
            if all(recent)
                push!(keys_to_prune, key)
            end
        end
    end

    for key in keys_to_prune
        delete!(_OUTCOME_HISTORY, key)
    end

    return newly_quarantined
end

"""
    clear_quarantine_on_consistent(ref::TestItemRef; window::Int=5) -> Bool

If a quarantined test has been consistently passing (no failures in the
last `window` outcomes), remove it from quarantine. Returns true if
quarantine was cleared.
"""
function clear_quarantine_on_consistent(ref::TestItemRef; window::Int=5)::Bool
    key = (ref.file, ref.name)
    key ∉ _QUARANTINED_TESTS && return false

    history = get(_OUTCOME_HISTORY, key, Bool[])
    if isempty(history)
        return false
    end
    recent = history[max(1, end - window + 1):end]
    if all(recent)
        delete!(_QUARANTINED_TESTS, key)
        return true
    end
    return false
end

# ── Manual edge persistence ────────────────────────

"""Default path for manual edge storage."""
const MANUAL_EDGES_PATH = joinpath(".testimonial", "manual_edges.jls")

"""A manual edge forcing selection of a test when content changes.

When `content_path` is modified in a future diff, `test` SHALL be
included in the selected set regardless of what the coverage index
would otherwise recommend.

Equality is based on (content_path, test) — timestamp is excluded.
"""
struct ManualEdge
    content_path :: String
    test :: TestItemRef
    created_at :: DateTime
end

function Base.:(==)(a::ManualEdge, b::ManualEdge)
    return a.content_path == b.content_path && a.test == b.test
end

function Base.hash(a::ManualEdge, h::UInt)
    return hash(a.content_path, hash(a.test, h))
end

"""
    save_manual_edges(edges::Vector{ManualEdge}, path::String=MANUAL_EDGES_PATH)

Persist manual edges to disk. Uses atomic write (tmp + rename).
"""
function save_manual_edges(edges::Vector{ManualEdge}, path::String=MANUAL_EDGES_PATH)
    dir = dirname(path)
    mkpath(dir)
    tmppath = path * ".tmp"
    open(tmppath, "w") do io
        serialize(io, edges)
    end
    mv(tmppath, path; force=true)
    return nothing
end

"""
    load_manual_edges(path::String=MANUAL_EDGES_PATH) -> Vector{ManualEdge}

Load persisted manual edges from disk.
Returns an empty vector if the file doesn't exist, can't be read,
or fails deserialization.
"""
function load_manual_edges(path::String=MANUAL_EDGES_PATH)::Vector{ManualEdge}
    if !isfile(path)
        return ManualEdge[]
    end
    try
        result = open(deserialize, path, "r")
        if result isa Vector{ManualEdge}
            return result
        end
        return ManualEdge[]
    catch
        return ManualEdge[]
    end
end

"""
    create_manual_edges_from_promoted(incidents; path::String=MANUAL_EDGES_PATH)

Extract promoted incidents, create `ManualEdge` entries for each
(changed_content, missed_test) pair, merge with existing edges,
and save.

Returns the updated vector of all manual edges.
"""
function create_manual_edges_from_promoted(
    incidents::Vector{MissedSelectionIncident};
    path::String=MANUAL_EDGES_PATH,
)::Vector{ManualEdge}
    # Collect existing edges
    existing = load_manual_edges(path)
    existing_set = Set(existing)

    # Create new edges from promoted incidents
    now_ts = now()
    for inc in incidents
        if inc.status == Promoted
            edge = ManualEdge(inc.changed_content, inc.missed_test, now_ts)
            push!(existing_set, edge)
        end
    end

    result = collect(existing_set)
    save_manual_edges(result, path)
    return result
end

# ── Shard balancing (duration-based) ──────────────

"""
    balance_shards(items, durations, n_shards) -> Vector{Vector{TestItemRef}}

Assign test items to shards using greedy duration-balancing.

Sorts items by descending mean duration, then assigns each item to the
shard with the lowest current total wall-clock time. Items without a
recorded duration (not in the `durations` dict) are treated as having
duration 0 and are assigned round-robin after duration-bearing items.

See Decision 4 in openspec/changes/add-component-boundary/design.md:
"Tests in the selected set are assigned to shards using a greedy
duration-balancing algorithm (sort by descending mean duration, assign
each to the currently lightest shard)."

# Arguments
- `items::Vector{TestItemRef}`: the tests to distribute across shards.
- `durations::Dict{Tuple{String, String}, Float64}`: per-test mean
  durations, keyed by `(file, name)` — as returned by `read_durations`.
- `n_shards::Int`: number of shards to create (must be ≥ 1).

# Returns
A vector of `n_shards` vectors, each containing the `TestItemRef`s
assigned to that shard. Shards are ordered by index 1..n_shards.

# Examples
```julia
items = [TestItemRef("test/a.jl", 10, "test_a"), TestItemRef("test/b.jl", 5, "test_b")]
durs = Dict(("test/a.jl", "test_a") => 5.0, ("test/b.jl", "test_b") => 3.0)
shards = balance_shards(items, durs, 2)
# shards[1] = [TestItemRef("test/a.jl", ...)]  # total 5.0
# shards[2] = [TestItemRef("test/b.jl", ...)]  # total 3.0
```
"""
function balance_shards(
    items::Vector{TestItemRef},
    durations::Dict{Tuple{String, String}, Float64},
    n_shards::Int
)::Vector{Vector{TestItemRef}}
    n_shards <= 0 && throw(ArgumentError("n_shards must be ≥ 1, got $n_shards"))

    shards = [TestItemRef[] for _ in 1:n_shards]
    shard_totals = zeros(Float64, n_shards)

    # Separate items with and without known durations
    has_duration = TestItemRef[]
    no_duration = TestItemRef[]
    for item in items
        key = (item.file, item.name)
        if haskey(durations, key) && durations[key] > 0
            push!(has_duration, item)
        else
            push!(no_duration, item)
        end
    end

    # Sort items with durations by descending duration
    sort!(has_duration; by=item -> -get(durations, (item.file, item.name), 0.0))

    # Greedy assignment: each item goes to the currently lightest shard
    for item in has_duration
        dur = durations[(item.file, item.name)]
        idx = argmin(shard_totals)
        push!(shards[idx], item)
        shard_totals[idx] += dur
    end

    # Items without recorded durations: round-robin across shards
    for (i, item) in enumerate(no_duration)
        idx = ((i - 1) % n_shards) + 1
        push!(shards[idx], item)
    end

    return shards
end

# ════════════════════════════════════════════
# 2. Protocol adapter (depends on core types)
# ════════════════════════════════════════════

include("Protocol.jl")
using .Protocol
export run_adapter_protocol

# ════════════════════════════════════════════
# 3. CLI entry points (depends on core types)
# ════════════════════════════════════════════

include("CLI.jl")
using .CLI
export index_info, explain, SCHEMA_VERSION, STALE_INDEX_THRESHOLD_HOURS

# ════════════════════════════════════════════
# 4. Confidence scoring (depends on core types)
# ════════════════════════════════════════════

"""Default stale threshold in hours for freshness signal (48h)."""
const DEFAULT_STALE_THRESHOLD_HOURS = 48

"""Default confidence threshold (0.7)."""
const DEFAULT_CONFIDENCE_THRESHOLD = 0.7

"""
    ConfidenceConfig

Parsed confidence scoring configuration from Testimonial.toml.

# Fields
- `threshold::Float64`: global confidence threshold (default 0.7, clamped to [0, 1])
- `component_overrides::Dict{Symbol, Float64}`: per-component threshold overrides

Example TOML:
```toml
[confidence]
threshold = 0.7

[confidence.components]
PkgA = 0.5
PkgB = 0.8
```
"""
struct ConfidenceConfig
    threshold :: Float64
    component_overrides :: Dict{Symbol, Float64}
end

# Default: global threshold 0.7, no per-component overrides
ConfidenceConfig() = ConfidenceConfig(DEFAULT_CONFIDENCE_THRESHOLD, Dict{Symbol, Float64}())

"""
    _freshness_signal(index) -> Float64

Compute the freshness quality signal for a coverage index.

Returns a value in [0, 1] representing how fresh the index is,
based on the elapsed time since `created_at`. Decays linearly
from 1.0 (just created) to 0.0 (at or past `stale_threshold_hours`).
"""
function _freshness_signal(index::CoverageIndex; stale_threshold_hours::Float64=Float64(DEFAULT_STALE_THRESHOLD_HOURS))::Float64
    age_hours = (now() - index.created_at) / Millisecond(3_600_000)
    return max(0.0, 1.0 - min(age_hours / stale_threshold_hours, 1.0))
end

"""
    _recording_quality_signal(index) -> Float64

Compute the recording quality signal for a coverage index.

Returns a value in [0, 1] based on the proportion of test items
that failed during recording: 1 - (failed_items / total_items).

Returns 1.0 if no items were recorded (zero total).
"""
function _recording_quality_signal(index::CoverageIndex)::Float64
    total = index.total_discovered_items
    if total == 0
        return 1.0
    end
    failed = index.failed_item_count
    return max(0.0, 1.0 - Float64(failed) / Float64(total))
end

"""
    _layer_coverage_signal(index) -> Float64

Compute the layer coverage signal for a coverage index.

Returns n / (n + 1) where n is the number of analysis layers that
contributed to the index (1 → 0.5, 2 → 0.67, 3 → 0.75, etc.).
Returns 0.0 if the index is empty (no layers).
"""
function _layer_coverage_signal(index::CoverageIndex)::Float64
    n = index.available_layers
    if n <= 0
        return 0.0
    end
    return Float64(n) / Float64(n + 1)
end

"""
    _history_quality_signal(ref, index, [run_history]) -> Float64

Compute the history quality signal for a test item.

Returns 1 - failure_rate from the test's run history entry.
Returns 1.0 if the test has no recorded history.
"""
function _history_quality_signal(ref::TestItemRef, index::CoverageIndex, run_history::RunHistory)::Float64
    key = (ref.file, ref.name)
    entry = get(run_history.outcome_entries, key, nothing)
    if entry === nothing
        return 1.0
    end
    return max(0.0, 1.0 - entry.failure_rate)
end

function _history_quality_signal(ref::TestItemRef, index::CoverageIndex)::Float64
    return _history_quality_signal(ref, index, RunHistory())
end

"""
    compute_confidence(test_ref, index) -> Float64

Compute a composite confidence score for a test item based on its
coverage index quality.

The score is the geometric mean of four quality signals:
- freshness (age of the index)
- recording quality (failure rate during recording)
- layer coverage (how many analysis layers contributed)
- history quality (historical pass/fail rate)

Returns a value in [0, 1]. Higher = more confident the selection is correct.

!!! warning "Not a probability"
    Confidence is a **heuristic**, not a correctness probability. A score of
    0.85 does not mean "85% chance of being correct." It is a relative quality
    signal used for fallback gating. When in doubt, run the full suite.
    See `openspec/changes/add-confidence-scoring/design.md` for details.
"""
function compute_confidence(test_ref::TestItemRef, index::CoverageIndex; stale_threshold_hours::Float64=Float64(DEFAULT_STALE_THRESHOLD_HOURS), run_history::RunHistory=RunHistory())::Float64
    f = _freshness_signal(index; stale_threshold_hours=stale_threshold_hours)
    r = _recording_quality_signal(index)
    l = _layer_coverage_signal(index)
    h = _history_quality_signal(test_ref, index, run_history)

    product = f * r * l * h
    if product == 0.0
        return 0.0
    end

    # Geometric mean: (f * r * l * h)^(1/4)
    return product^0.25
end

"""
    parse_confidence_config(config::Dict) -> ConfidenceConfig

Parse the `[confidence]` section from a Testimonial.toml config dict.

Expected format:
```toml
[confidence]
threshold = 0.7

[confidence.components]
PkgA = 0.5
PkgB = 0.8
```

Thresholds are clamped to [0, 1]. Returns a default `ConfidenceConfig`
if no `[confidence]` section exists.
"""
function parse_confidence_config(config::Dict)::ConfidenceConfig
    if !haskey(config, "confidence") || !isa(config["confidence"], Dict)
        return ConfidenceConfig()
    end
    conf = config["confidence"]

    threshold = if haskey(conf, "threshold") && isa(conf["threshold"], Number)
        clamp(Float64(conf["threshold"]), 0.0, 1.0)
    else
        DEFAULT_CONFIDENCE_THRESHOLD
    end

    overrides = Dict{Symbol, Float64}()
    if haskey(conf, "components") && isa(conf["components"], Dict)
        comps = conf["components"]
        for (name, val) in comps
            if isa(val, Number)
                overrides[Symbol(name)] = clamp(Float64(val), 0.0, 1.0)
            end
        end
    end

    return ConfidenceConfig(threshold, overrides)
end

"""
    group_items_by_component(items) -> Dict{Symbol, Vector{TestItemRef}}

Group test items by their component name.

Items with an empty component string are placed under a single key
based on their file path prefix. Returns a dict mapping each component
name to its vector of TestItemRefs. Returns an empty dict for empty input.
"""
function group_items_by_component(items::Vector{TestItemRef})::Dict{Symbol, Vector{TestItemRef}}
    grouped = Dict{Symbol, Vector{TestItemRef}}()
    for item in items
        comp = isempty(item.component) ? :__unmapped__ : Symbol(item.component)
        if haskey(grouped, comp)
            push!(grouped[comp], item)
        else
            grouped[comp] = [item]
        end
    end
    return grouped
end

"""
    compute_component_confidence(items, index; kwargs...) -> Dict{Symbol, Float64}

Compute the minimum per-test confidence score for each component.

Groups items by component, computes compute_confidence for each item,
and returns the minimum score per component. Additional keyword arguments
(e.g., stale_threshold_hours, run_history) are forwarded to
compute_confidence.

Returns an empty dict if `items` is empty.
"""
function compute_component_confidence(items::Vector{TestItemRef}, index::CoverageIndex; kwargs...)::Dict{Symbol, Float64}
    isempty(items) && return Dict{Symbol, Float64}()

    grouped = group_items_by_component(items)
    result = Dict{Symbol, Float64}()

    for (comp, comp_items) in grouped
        min_score = 1.0
        for item in comp_items
            score = compute_confidence(item, index; kwargs...)
            if score < min_score
                min_score = score
            end
        end
        result[comp] = min_score
    end

    return result
end

"""
    format_confidence_summary(component_confidences) -> String

Format a per-component confidence summary for display.

Returns a multiline string like:
  Confidence:
    PkgA: 0.85
    PkgB: 0.72

Returns an empty string for empty input.
"""
function format_confidence_summary(component_confidences::Dict{Symbol, Float64})::String
    isempty(component_confidences) && return ""

    lines = String["Confidence:"]
    for (comp, score) in sort(collect(component_confidences), by=first)
        formatted = string(round(score, digits=2))
        push!(lines, string("  ", string(comp), ": ", formatted))
    end
    return join(lines, "\n")
end

"""
    summarize_selection(items, index; kwargs...) -> String

Produce a human-readable selection summary including per-component
confidence scores. Calls compute_component_confidence internally.

!!! note
    Confidence values are heuristics, not probabilities. They indicate
    relative selection quality — use the threshold for fallback decisions.
"""
function summarize_selection(items::Vector{TestItemRef}, index::CoverageIndex; kwargs...)::String
    parts = String[]
    push!(parts, "Selected $(length(items)) test(s)")

    conf = compute_component_confidence(items, index; kwargs...)
    conf_str = format_confidence_summary(conf)
    if !isempty(conf_str)
        push!(parts, conf_str)
    end

    return join(parts, "\n")
end

"""
    components_below_threshold(component_confidences, config) -> Vector{Symbol}

Return the list of components whose minimum confidence is below their
configured threshold.

Returns an empty vector if no components fall below threshold.
The global threshold is used as a fallback for components without overrides.
"""
function components_below_threshold(
    component_confidences::Dict{Symbol, Float64},
    config::ConfidenceConfig,
)::Vector{Symbol}
    below = Symbol[]
    for (comp, score) in component_confidences
        threshold = get(config.component_overrides, comp, config.threshold)
        if score < threshold
            push!(below, comp)
        end
    end
    return below
end

export compute_confidence, DEFAULT_STALE_THRESHOLD_HOURS, DEFAULT_CONFIDENCE_THRESHOLD,
       ConfidenceConfig, parse_confidence_config, group_items_by_component,
       compute_component_confidence, format_confidence_summary, summarize_selection,
       components_below_threshold

# ════════════════════════════════════════════
# 5. Sub-modules (may depend on types + CLI/Protocol)
# ════════════════════════════════════════════

include("GitDiff.jl")
using .GitDiff
export parse_unified_diff

include("CoverageLayer.jl")
using .CoverageLayer
export record_item, record_batch, build_driver_command, AbstractRunner, SubprocessRunner, parse_cov_sidecar

include("IndexBuilder.jl")
using .IndexBuilder
export record_all, build_index, save_index, load_index, is_index_stale, clean_cache, migrate_index, build_component_graph!, save_component_graph, load_component_graph, compute_dependency_fingerprint, save_fingerprint, load_fingerprint, save_selection_cache, load_selection_cache, invalidate_selection_cache, invalidate_all_selection_caches

include("Query.jl")
using .Query
export query, query_files, coverage_gaps, nearest_covered_lines
export direct_change_provider, unresolved_provider, must_run_provider,
       manual_edge_provider, runtime_edge_provider, external_input_provider,
       coverage_provider

# ════════════════════════════════════════════
# 5. Extensions
# ════════════════════════════════════════════

import .CoverageLayer: record_item
function record_item(test_file::AbstractString, item_name::AbstractString)
    return IndexBuilder._record_single_item(test_file, item_name)
end

end # module Testimonial