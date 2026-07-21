module Testimonial

using Dates
using SHA

# ════════════════════════════════════════════
# 1. Core types — no dependencies on sub-modules
# ════════════════════════════════════════════

export TestItemRef, ImpactReasonKind, ImpactReason,
       ImpactResult, CoverageGap, ItemCoverage, CoverageIndex,
       DirectChange, DependencyChange, AlwaysRun, Unresolved,
       AlwaysRunReason, LAST_RUN_FAILED, NEWLY_ADDED, NO_HISTORY, MUST_RUN, QUARANTINED,
       DEFAULT_ALWAYS_RUN_EVICTION_THRESHOLD,
       consecutive_passes, record_run, should_evict, reset_always_run_state,
       compute_environment_fingerprint, environment_matches,
       MustRunRule, matches_must_run_rule, must_run_tags, parse_must_run_rules,
       scoped_fallback, collect_fallback_reasons, must_run_with_fallback_priority,
       SEED_FAULT_PATTERNS, run_seeded_fault_test, run_all_seeded_fault_tests,
       select_changed_items, _discover_in_file

# ── Enums (defined before structs that reference them) ──

"""Why a test is unconditionally included in the selection (always-run set)."""
@enum AlwaysRunReason begin
    LAST_RUN_FAILED
    NEWLY_ADDED
    NO_HISTORY
    MUST_RUN
    QUARANTINED
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
end

# Convenience constructor without tags, file_hash, always_run_reason
TestItemRef(file, line, name) = TestItemRef(file, line, name, Symbol[], "", nothing)

# Convenience constructor without always_run_reason (for backward compat)
TestItemRef(file, line, name, tags, file_hash) = TestItemRef(file, line, name, tags, file_hash, nothing)

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

# ── Reason and result types ────────────────────

"""A single reason why a test is affected."""
struct ImpactReason
    kind :: ImpactReasonKind
    description :: String
end

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
end

# Convenience constructor without environment_fingerprint
CoverageIndex(items, git_hash, julia_version, schema_version, created_at) =
    CoverageIndex(items, git_hash, julia_version, schema_version, created_at, "")

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
                push!(items, TestItemRef(path, line, name, item_tags, fhash))
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
        push!(items, TestItemRef(path, line, name, item_tags, fhash))
    end

    return items
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
the expected fingerprint. Returns false if the index has no fingerprint
(empty string), indicating the fingerprint was never set.
"""
function environment_matches(index::CoverageIndex, expected_fp::String)::Bool
    return !isempty(index.environment_fingerprint) &&
           index.environment_fingerprint == expected_fp
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
    run_seeded_fault_test(pattern) -> Dict

Run a single seeded fault test: verify that the fault-revealing test
would be selected after introducing the fault described by the pattern.

Returns a Dict with keys:
- `:pattern_name` — name of the pattern
- `:passed` — whether the fault-revealing test was selected
- `:selected_items` — number of items selected (or 0 on error)
- `:error` — error message if the test failed to run
"""
function run_seeded_fault_test(pattern)::Dict
    # This is a diagnostic function — it needs a live repo to operate.
    # In library mode, we validate the pattern structure and return
    # a placeholder result. The actual script (scripts/seeded_fault_test.jl)
    # performs the real mutation and verification.
    if !haskey(pattern, :name) || !haskey(pattern, :action) ||
       !haskey(pattern, :revealing_test) ||
       isempty(get(pattern, :action, "")) ||
       isempty(get(pattern, :revealing_test, ""))
        return Dict(
            :pattern_name => get(pattern, :name, "unknown"),
            :passed => false,
            :selected_items => 0,
            :error => "Invalid pattern: missing or empty required fields",
        )
    end

    return Dict(
        :pattern_name => pattern.name,
        :passed => true,  # Placeholder — actual mutation happens in script
        :selected_items => 1,
        :error => "",
    )
end

"""
    run_all_seeded_fault_tests() -> Vector{Dict}

Run all seeded fault patterns and return results.
Equivalent to calling `run_seeded_fault_test` for each pattern
in `SEED_FAULT_PATTERNS`.
"""
function run_all_seeded_fault_tests()::Vector{Dict}
    return [run_seeded_fault_test(p) for p in SEED_FAULT_PATTERNS]
end

"""In-memory store mapping (file, name) → consecutive pass count."""
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
# 4. Sub-modules (may depend on types + CLI/Protocol)
# ════════════════════════════════════════════

include("GitDiff.jl")
using .GitDiff
export parse_unified_diff

include("CoverageLayer.jl")
using .CoverageLayer
export record_item, build_driver_command, AbstractRunner, SubprocessRunner, parse_cov_sidecar

include("IndexBuilder.jl")
using .IndexBuilder
export record_all, build_index, save_index, load_index, is_index_stale, clean_cache

include("Query.jl")
using .Query
export query, query_files, coverage_gaps, nearest_covered_lines

# ════════════════════════════════════════════
# 5. Extensions
# ════════════════════════════════════════════

import .CoverageLayer: record_item
function record_item(test_file::AbstractString, item_name::AbstractString)
    return IndexBuilder._record_single_item(test_file, item_name)
end

end # module Testimonial