#!/usr/bin/env julia
#
# TestimonialRunner driver.jl — subprocess entry point for recording coverage
# of individual @testitems.
#
# Usage:
#   TESTIMONIAL_FILE=test/my_test.jl TESTIMONIAL_ITEM="My test" julia driver.jl
#   TESTIMONIAL_FILE=test/my_test.jl TESTIMONIAL_ITEMS="My test\nOther test" julia driver.jl
#
# Reads TESTIMONIAL_FILE and either TESTIMONIAL_ITEM (single) or
# TESTIMONIAL_ITEMS (newline-separated batch) from the environment, runs
# the specified @testitem(s) via ReTestItems.runtests, and exits with
# a status code indicating the outcome.
#
# Batch mode runs every named item sequentially within one Julia process;
# the LCOV tracefile therefore holds the UNION of coverage across the
# batch (safe over-approximation attributed per-item by the caller).
#
# Exit codes:
#   0 — Success (test ran, result printed to stdout)
#   2 — Internal Error (unhandled exception in the driver itself)
#   3 — Setup Error (missing env vars, file not found, dependency issue)
#
# Note: Test pass/fail is reported in stdout output, not via exit code.
# ReTestItems.runtests does not throw on test failures.
#
# See REC-009 in openspec/changes/implement-coverage-layer/specs/recording/spec.md

using ReTestItems
using Serialization

# ── Optional SnoopCompile loading ────────────
# SnoopCompile v3 (Julia ≥ 1.12, @snoop_inference → tree) or v2
# (Julia < 1.12, @snoopi_deep → table).  Detects the available API
# at load time; if neither is available, inference capture is skipped.
const HAS_SNOOPCOMPILE = Ref(false)
const USE_V3_API = Ref(false)  # false → v2 API
try
    @eval using SnoopCompile
    HAS_SNOOPCOMPILE[] = true
    USE_V3_API[] = isdefined(SnoopCompile, Symbol("@snoop_inference"))
catch
    HAS_SNOOPCOMPILE[] = false
end

# ── Inference edge extraction ────────────────
# Both v2 and v3 APIs produce the same sidecar format: a Vector of
# (caller_name, caller_file, caller_line, callee_name, callee_file,
# callee_line) tuples.  Plain primitives only — result serializes
# cleanly without SnoopCompile on the reading side (testimonial-be7o).

"""
    _mi_def_loc(mi) -> Union{Tuple{String,String,Int}, Nothing}

Return (name, file, line) for a MethodInstance's def, or `nothing`
if the def is not a `Method`.
"""
function _mi_def_loc(mi)
    def = mi.def
    def isa Method || return nothing
    return (String(def.name), String(def.file), Int(def.line))
end

# ── v3 extraction: InferenceTimingNode tree ───

"""
    _method_loc(node) -> Union{Tuple{String,String,Int}, Nothing}

Return (name, file, line) for a v3-style InferenceTimingNode's method,
or `nothing` if not a `Method`.
"""
function _method_loc(node)
    mi = try
        Core.Compiler.get_ci_mi(node.ci)
    catch
        return nothing
    end
    return _mi_def_loc(mi)
end

"""
    _walk_inference_tree!(edges, node)

Recursively traverse a v3 inference tree, pushing caller→callee edges.
"""
function _walk_inference_tree!(edges, node)
    callee = _method_loc(node)
    callee === nothing && return
    if isdefined(node, :parent) && node.parent !== node && isdefined(node.parent, :ci)
        caller = _method_loc(node.parent)
        caller !== nothing && push!(edges, (caller..., callee...))
    end
    for child in node.children
        _walk_inference_tree!(edges, child)
    end
    return edges
end

"""
    _extract_edges_tree(root) -> Vector{Tuple{String,String,Int,String,String,Int}}

Extract caller→callee edges from a v3-style @snoop_inference tree.
"""
function _extract_edges_tree(root)
    edges = Tuple{String,String,Int,String,String,Int}[]
    isdefined(root, :ci) || return edges
    _walk_inference_tree!(edges, root)
    return edges
end

# ── v2 extraction: InferenceTimingTable ──────

"""
    _extract_edges_table(timing) -> Vector

Extract caller→callee edges from a v2-style InferenceTimingTable.
Table columns: .mi (MethodInstances) and .parentidx (caller row).
"""
function _extract_edges_table(timing)
    edges = Tuple{String,String,Int,String,String,Int}[]
    for i in 1:length(timing.mi)
        pi = timing.parentidx[i]
        pi > 0 || continue
        callee = _mi_def_loc(timing.mi[i])
        callee === nothing && continue
        caller = _mi_def_loc(timing.mi[pi])
        caller === nothing && continue
        push!(edges, (caller..., callee...))
    end
    return edges
end

# ── Runtime macro dispatch ──────────────────
# Macro invocations are resolved at parse time, so we cannot have both
# @snoop_inference and @snoopi_deep in the same source file.  Instead
# build the capture expression via string interpolation and eval it at
# runtime, AFTER the API version has been selected.

"""
    _capture_item(test_file, item_names, use_v3) -> result

Run the test(s) under the appropriate SnoopCompile macro and return the
captured inference data (InferenceTimingNode tree in v3,
InferenceTimingTable in v2).
"""
function _capture_item(test_file::String, item_names::Vector{String}, use_v3::Bool)
    test_repr = repr(test_file)
    names_repr = repr(item_names)
    macro_name = use_v3 ? "SnoopCompile.@snoop_inference" : "SnoopCompile.@snoopi_deep"
    code = """
        result = $macro_name begin
            for item in $names_repr
                ReTestItems.runtests($test_repr; name=item)
            end
        end
    """
    return eval(Meta.parse(code))
end

# ── Read environment ──────────────────────────

test_file = get(ENV, "TESTIMONIAL_FILE", nothing)
test_run_all = get(ENV, "TESTIMONIAL_RUN_ALL", nothing) == "true"
test_item = get(ENV, "TESTIMONIAL_ITEM", nothing)
test_items_raw = get(ENV, "TESTIMONIAL_ITEMS", nothing)

if test_file === nothing
    println(stderr, "driver.jl: missing TESTIMONIAL_FILE")
    exit(3)
end

if test_run_all
    # File-level mode: run all tests in the file without filtering by name
    item_names = String[]
    # Pass the test file directly to runtests
else
    # Batch form takes precedence; single-item form is the fallback.
    item_names = if test_items_raw !== nothing
        filter(!isempty, split(test_items_raw, "\n"))
    else
        test_item === nothing ? String[] : String[test_item]
    end

    if isempty(item_names)
        println(stderr, "driver.jl: missing TESTIMONIAL_ITEM or TESTIMONIAL_ITEMS")
        exit(3)
    end
end

if !isfile(test_file)
    println(stderr, "driver.jl: test file not found: $(test_file)")
    exit(3)
end

# ── Activate the project under test ──────────
# The test file belongs to a project (e.g., TestJuliaAdapter).
# Walk up from the test file to find a Project.toml and activate it
# so ReTestItems can find the @testitem blocks and the project's deps.
test_dir = dirname(realpath(test_file))
function _find_project_root(start_dir)
    d = start_dir
    while true
        if isfile(joinpath(d, "Project.toml"))
            return d
        end
        parent = dirname(d)
        if parent == d
            return dirname(start_dir)
        end
        d = parent
    end
end
pkg_under_test = _find_project_root(test_dir)

# Add the project to the load path so ReTestItems can find its test files
push!(LOAD_PATH, pkg_under_test)

# ── Run the test(s) under SnoopCompile capture ─
# The resulting caller→callee edges are serialized to `inference_trace.jls`
# in pwd, consumed by testimonial-be7o.  If SnoopCompile is unavailable,
# inference capture is skipped (coverage-only fallback).

trace_path = if haskey(ENV, "TESTIMONIAL_TRACE_OUTPUT_DIR")
    joinpath(ENV["TESTIMONIAL_TRACE_OUTPUT_DIR"], "inference_trace.jls")
else
    joinpath(pwd(), "inference_trace.jls")
end

try
    if test_run_all
        # File-level mode: run all tests in the file without filtering
        if HAS_SNOOPCOMPILE[]
            result = _capture_item(test_file, String[], USE_V3_API[])
            extract_fn = USE_V3_API[] ? _extract_edges_tree : _extract_edges_table
            edges = extract_fn(result)
            Serialization.serialize(trace_path, edges)
        else
            ReTestItems.runtests(test_file)
        end
    elseif HAS_SNOOPCOMPILE[]
        result = _capture_item(test_file, item_names, USE_V3_API[])
        extract_fn = USE_V3_API[] ? _extract_edges_tree : _extract_edges_table
        edges = extract_fn(result)
        Serialization.serialize(trace_path, edges)
    else
        for item in item_names
            ReTestItems.runtests(test_file; name=item)
        end
    end
    # runtests prints results to stdout; if it returns without
    # throwing, the test ran successfully (exit 0).
    # Test failures are reported in the output but don't throw.
    exit(0)
catch e
    if e isa ArgumentError || e isa SystemError || e isa ReTestItems.NoTestException
        println(stderr, "driver.jl: setup error: $(sprint(showerror, e))")
        exit(3)
    else
        println(stderr, "driver.jl: internal error: $(sprint(showerror, e))")
        exit(2)
    end
end