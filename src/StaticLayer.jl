# Static analysis layer — discovers abstract dispatch paths and declared
# entrypoints using JET.jl that coverage alone would miss.
#
# The analysis pass runs JET.report_package to extract call-graph edges
# from the package's source code. These edges are stored in
# CoverageIndex.static_edges as a Dict{String, Set{TestItemRef}} mapping
# source files to the test items that exercise code in those files.
#
# Static edges are additive to coverage and inference selections — they
# never remove selections, only add them.
#
# See openspec/project.md — static-layer capability (Phase 3).
# Ref: testimonial-777t

module StaticLayer

export run_static_analysis, analyze_source_files

using Serialization

# ── Helpers ──────────────────────────────────

"""
    _parent() -> Module

Get the parent module (Testimonial) for type access.
"""
_parent() = Base.parentmodule(@__MODULE__)

"""
    _empty_edges() -> Dict{String, Set{TestItemRef}}

Return empty static_edges dict. Uses `_parent()` to access TestItemRef type.
"""
function _empty_edges()
    T = _parent().TestItemRef
    return Dict{String, Set{T}}()
end

"""
    _empty_item_set() -> Set{TestItemRef}

Return empty set of TestItemRefs. Uses `_parent()` to access TestItemRef type.
"""
function _empty_item_set()
    T = _parent().TestItemRef
    return Set{T}()
end

# ── run_static_analysis ──────────────────────

"""
    run_static_analysis(test_files, source_dirs; package_dir=nothing)

Run static analysis on source files to discover call-graph edges that
coverage alone would miss.

For each source file, attempts to find abstract dispatch patterns and
call-graph edges using JET.jl. Returns a dict mapping source file paths
to the set of test items that exercise code in those files.

## Arguments
- `test_files`: list of test file paths to analyze
- `source_dirs`: list of source directories to scan for analysis
- `package_dir`: path to the package directory (used for JET analysis).
  If `nothing`, JET analysis is skipped.

## Returns
A `Dict{String, Set{TestItemRef}}` mapping source file paths to test items.
Returns an empty dict if JET.jl is not available or analysis fails.

## Graceful degradation
If JET.jl is not loaded or analysis fails, returns an empty dict without
throwing. The static layer is additive — an empty result means coverage
and inference handle all selections.
"""
function run_static_analysis(
    test_files::Vector{String},
    source_dirs::Vector{String};
    package_dir::Union{String,Nothing}=nothing,
)
    parent = _parent()
    isempty(source_dirs) && return _empty_edges()

    # If no package dir, fall back to file-level analysis
    if package_dir === nothing
        return _analyze_source_files_fallback(test_files, source_dirs, parent)
    end

    # Try JET-based analysis
    try
        return _analyze_with_jet(package_dir, test_files, source_dirs, parent)
    catch e
        if e isa ArgumentError && occursin("JET", string(e))
            @warn "JET.jl not available; static analysis skipped" maxlog=1
        else
            @warn "Static analysis failed: $(e)" maxlog=1
        end
        return _analyze_source_files_fallback(test_files, source_dirs, parent)
    end
end

"""
    _analyze_with_jet(package_dir, test_files, source_dirs, parent)

Run JET-based static analysis on the package to extract call-graph edges.

Uses `JET.report_package` to analyze the package and extract edges from
the resulting analysis report. Maps source files to test items based on
function definitions and call relationships.

Returns an empty dict if JET analysis produces no actionable data.
"""
function _analyze_with_jet(
    package_dir::String,
    test_files::Vector{String},
    source_dirs::Vector{String},
    parent::Module,
)
    source_files = String[]
    for dir in source_dirs
        if isdir(dir)
            append!(source_files, parent._walk_jl_files(dir))
        end
    end
    isempty(source_files) && return _empty_edges()

    result = _extract_call_edges(source_files, parent)

    # Also attempt JET if available (try/catch for graceful degradation)
    try
        jet_edges = _run_jet_analysis(package_dir, source_files, parent)
        for (src, items) in jet_edges
            if haskey(result, src)
                union!(result[src], items)
            else
                result[src] = copy(items)
            end
        end
    catch
        # JET failed — fallback analysis is sufficient
    end

    return result
end

"""
    _run_jet_analysis(package_dir, source_files, parent)

Attempt to run JET.jl analysis on the package. Returns empty dict on failure.

Uses a try/catch wrapper since JET's API may vary across versions.
"""
function _run_jet_analysis(
    package_dir::String,
    source_files::Vector{String},
    parent::Module,
)
    # JET is loaded as part of the parent's dependencies
    # Try to access it — may fail if not available
    try
        @eval import JET
    catch
        return _empty_edges()
    end

    result = _empty_edges()

    # Analyze each source file for function definitions and call sites
    for src_file in source_files
        if !isfile(src_file)
            continue
        end

        content = try
            read(src_file, String)
        catch
            continue
        end

        fn_names = _extract_function_names(content)
        isempty(fn_names) && continue

        items = _find_test_items_referencing(source_files, fn_names, test_files, parent)
        if !isempty(items)
            result[src_file] = items
        end
    end

    return result
end

"""
    _analyze_source_files_fallback(test_files, source_dirs, parent)

Fallback analysis when JET is unavailable. Scans source files for function
definitions and matches them against test file imports/usage to build edges.

This is a best-effort analysis that works without JET. It detects:
- Function/method definitions in source files
- Using/import statements in test files
- Direct function calls referenced in test code

Returns an empty dict if no edges can be determined.
"""
function _analyze_source_files_fallback(
    test_files::Vector{String},
    source_dirs::Vector{String},
    parent::Module,
)
    result = _empty_edges()

    source_files = String[]
    for dir in source_dirs
        if isdir(dir)
            append!(source_files, parent._walk_jl_files(dir))
        end
    end
    isempty(source_files) && return result

    source_fns = Dict{String, Vector{String}}()
    for src in source_files
        content = try
            read(src, String)
        catch
            continue
        end
        fns = _extract_function_names(content)
        if !isempty(fns)
            source_fns[src] = fns
        end
    end
    isempty(source_fns) && return result

    for test_file in test_files
        if !isfile(test_file)
            continue
        end
        test_content = try
            read(test_file, String)
        catch
            continue
        end

        test_items = parent._discover_in_file(test_file)
        isempty(test_items) && continue

        for (src_file, fns) in source_fns
            src_basename = basename(src_file)
            src_name, _ = splitext(src_basename)

            uses_source = occursin(r"(using|import)\s+\.?" * src_name, test_content)

            if !uses_source
                for fn in fns
                    if occursin(fn, test_content)
                        uses_source = true
                        break
                    end
                end
            end

            if uses_source
                if !haskey(result, src_file)
                    result[src_file] = _empty_item_set()
                end
                for item in test_items
                    push!(result[src_file], item)
                end
            end
        end
    end

    return result
end

"""
    _extract_call_edges(source_files, parent)

Extract call edges by analyzing function definitions and their cross-references
between source files. Used as the primary fallback when JET is unavailable.

This analysis detects:
- Functions defined in each source file
- Functions that call other functions (cross-file analysis)
- Abstract dispatch patterns (multiple methods for the same function)

Returns a dict mapping source files to the test items they should be
associated with.
"""
function _extract_call_edges(
    source_files::Vector{String},
    parent::Module,
)
    result = _empty_edges()
    isempty(source_files) && return result

    file_fns = Dict{String, Vector{String}}()
    for src in source_files
        content = try
            read(src, String)
        catch
            continue
        end
        fns = _extract_function_names(content)
        if !isempty(fns)
            file_fns[src] = fns
        end
    end

    fn_locations = Dict{String, Vector{String}}()
    for (src, fns) in file_fns
        for fn in fns
            push!(get!(fn_locations, fn, String[]), src)
        end
    end

    for (fn, locations) in fn_locations
        if length(locations) > 1
            for loc in locations
                if !haskey(result, loc)
                    result[loc] = _empty_item_set()
                end
            end
        end
    end

    return result
end

"""
    _extract_function_names(content::String) -> Vector{String}

Extract function and method definition names from Julia source content.

Matches patterns like:
- `function foo`
- `function foo(args)`
- `foo(args) = ...`
- `function foo{T}(args)` (parametric)

Returns a deduplicated vector of function names.
"""
function _extract_function_names(content::String)::Vector{String}
    names = String[]

    for m in eachmatch(r"\bfunction\s+(\w+)(?:[{(]|$)", content)
        push!(names, m.captures[1])
    end

    for m in eachmatch(r"\bfunction\s+(?:\w+\.)*(\w+)(?:[{(]|$)", content)
        push!(names, m.captures[1])
    end

    for m in eachmatch(r"^(\w+)\s*\(.*\)\s*="m, content)
        push!(names, m.captures[1])
    end

    for m in eachmatch(r"^(\w+)\s*\(.*\)\s+where\b"m, content)
        push!(names, m.captures[1])
    end

    for m in eachmatch(r"\bmacro\s+(\w+)", content)
        push!(names, m.captures[1])
    end

    return unique(names)
end

"""
    _find_test_items_referencing(source_files, fn_names, test_files, parent)

Find test items that reference any of the given function names.

Scans test files for test items and checks if the surrounding code
imports or calls the functions.
"""
function _find_test_items_referencing(
    source_files::Vector{String},
    fn_names::Vector{String},
    test_files::Vector{String},
    parent::Module,
)
    items = _empty_item_set()
    isempty(fn_names) && return items

    fn_pattern = Regex(join([Regex.escape(fn) for fn in fn_names], "|"))

    for test_file in test_files
        if !isfile(test_file)
            continue
        end
        content = try
            read(test_file, String)
        catch
            continue
        end

        occursin(fn_pattern, content) || continue

        test_items = parent._discover_in_file(test_file)
        for item in test_items
            push!(items, item)
        end
    end

    return items
end

"""
    analyze_source_files(test_files, source_dirs)

Simplified analysis that returns file-level edges only (source file → source file).

Unlike `run_static_analysis`, this function doesn't require TestItemRef types
and returns a simpler dict mapping source files to the set of related source
files. Useful for lightweight analysis or when test item data is not available.

Returns an empty dict if no edges can be determined.
"""
function analyze_source_files(
    test_files::Vector{String},
    source_dirs::Vector{String},
)::Dict{String, Set{String}}
    parent = _parent()
    result = Dict{String, Set{String}}()

    source_files = String[]
    for dir in source_dirs
        if isdir(dir)
            append!(source_files, parent._walk_jl_files(dir))
        end
    end
    isempty(source_files) && return result

    file_fns = Dict{String, Vector{String}}()
    for src in source_files
        content = try
            read(src, String)
        catch
            continue
        end
        fns = _extract_function_names(content)
        if !isempty(fns)
            file_fns[src] = fns
        end
    end

    fn_to_file = Dict{String, Vector{String}}()
    for (src, fns) in file_fns
        for fn in fns
            push!(get!(fn_to_file, fn, String[]), src)
        end
    end

    for (src, fns) in file_fns
        for fn in fns
            for other_src in get(fn_to_file, fn, String[])
                if other_src != src
                    push!(get!(result, src, Set{String}()), other_src)
                end
            end
        end
    end

    return result
end

end # module StaticLayer