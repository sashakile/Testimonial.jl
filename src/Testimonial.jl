module Testimonial

using Dates
using SHA

# Protocol adapter — JSON stdin/stdout protocol for testaruda integration
include("Protocol.jl")
using .Protocol

# CLI entry points
include("CLI.jl")
using .CLI
export index_info, explain, SCHEMA_VERSION, STALE_INDEX_THRESHOLD_HOURS

# Core types — the foundation of the coverage layer
export TestItemRef, ImpactReasonKind, ImpactReason,
       ImpactResult, CoverageGap, ItemCoverage, CoverageIndex,
       DirectChange, DependencyChange, AlwaysRun, Unresolved,
       select_changed_items, _discover_in_file

# Protocol adapter exports
export run_adapter_protocol

# ── Basic structs ──────────────────────────────

"""Reference to a single @testitem in a source file."""
struct TestItemRef
    file :: String
    line :: Int
    name :: String
    tags :: Vector{Symbol}
    file_hash :: String
end

# Convenience constructor without tags/file_hash
TestItemRef(file, line, name) = TestItemRef(file, line, name, Symbol[], "")

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
end

"""The full coverage index for a project snapshot."""
struct CoverageIndex
    items :: Dict{TestItemRef, ItemCoverage}
    git_hash :: String
    julia_version :: String
    schema_version :: VersionNumber
    created_at :: DateTime
end

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
    # Matches: @testitem "name" [tags=[:sym1, :sym2]] begin
    pattern = r"@testitem\s+\"([^\"]+)\"(?:\s+tags=\[([^\]]*)\])?"
    for m in eachmatch(pattern, content)
        name = m.captures[1]
        tags_str = m.captures[2]
        if isnothing(tags_str) || isempty(strip(tags_str))
            result[name] = Symbol[]
        else
            # Parse :sym1, :sym2 (strip leading colons)
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

"""
    _walk_jl_files(dir::String) -> Vector{String}

Recursively walk a directory and return all .jl files.
"""
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
            # Match @testitem on each line, converting byte offset to line number
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

"""
    _discover_in_file(path::String) -> Vector{TestItemRef}

Discover @testitem blocks in a single file. Returns a Vector{TestItemRef}
with one entry per @testitem found. Returns an empty vector if the file
cannot be read or contains no @testitem blocks.
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

# Examples
```julia
changed = ["src/foo.jl", "test/foo_test.jl", "README.md"]
items = select_changed_items(changed, ["test/"])
```
"""
function select_changed_items(changed_files::Vector{String}, test_dirs::Vector{String})::Vector{TestItemRef}
    # Normalize test directories to absolute paths
    abs_dirs = String[]
    for d in test_dirs
        push!(abs_dirs, isabspath(d) ? realpath(d) : abspath(d))
    end

    items = TestItemRef[]
    seen = Set{String}()

    for cf in changed_files
        # Normalize the changed file path
        abs_cf = isabspath(cf) ? cf : abspath(cf)

        # Check if the file is under any test directory
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

        # Skip files we've already scanned (duplicates in changed_files list)
        if abs_cf in seen
            continue
        end
        push!(seen, abs_cf)

        # Discover @testitems in this file
        append!(items, _discover_in_file(abs_cf))
    end

    return items
end
include("GitDiff.jl")
using .GitDiff
export parse_unified_diff

# Coverage layer — per-item recording
include("CoverageLayer.jl")
using .CoverageLayer
export record_item, build_driver_command, AbstractRunner, SubprocessRunner, parse_cov_sidecar

# Index builder — single-item and bulk recording
include("IndexBuilder.jl")
using .IndexBuilder
export record_all, build_index, save_index, load_index, is_index_stale

# Query engine — impact analysis from coverage index
include("Query.jl")
using .Query
export query, query_files, coverage_gaps, nearest_covered_lines

# Extend the CoverageLayer.record_item function with a convenience method
# that accepts (test_file, item_name) for single-item debugging.
# We use the function from CoverageLayer so both method signatures
# (one-arg ref and two-arg string) live on the same function object.
import .CoverageLayer: record_item
function record_item(test_file::AbstractString, item_name::AbstractString)
    return IndexBuilder._record_single_item(test_file, item_name)
end

end # module Testimonial
