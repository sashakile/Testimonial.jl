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
end

# Default: selected = true when reasons are present
function ImpactResult(item::TestItemRef, reasons::Vector{ImpactReason})
    ImpactResult(item, reasons, !isempty(reasons))
end

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