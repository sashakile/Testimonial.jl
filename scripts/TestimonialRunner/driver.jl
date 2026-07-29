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
using SnoopCompile
using Serialization

# ── Inference edge extraction ────────────────
# Walk the InferenceTimingNode tree produced by @snoop_inference and
# emit caller→callee edges as plain (name, file, line) tuples. Plain
# primitives only — the result serializes cleanly across processes
# without SnoopCompile on the reading side (see testimonial-be7o).

"""
    _method_loc(node) -> Union{Tuple{String,String,Int}, Nothing}

Return (name, file, line) for the node's inferred method, or `nothing`
if the node's def is not a `Method` (e.g. toplevel thunks).
"""
function _method_loc(node)
    mi = try
        Core.Compiler.get_ci_mi(node.ci)
    catch
        return nothing
    end
    def = mi.def
    def isa Method || return nothing
    return (String(def.name), String(def.file), Int(def.line))
end

"""
    _walk_inference!(edges, node)

Recursively traverse the inference tree. For every node whose parent is
a `Method`, push a (caller..., callee...) edge.
"""
function _walk_inference!(edges, node)
    callee = _method_loc(node)
    callee === nothing && return
    if isdefined(node, :parent) && node.parent !== node && isdefined(node.parent, :ci)
        caller = _method_loc(node.parent)
        caller !== nothing && push!(edges, (caller..., callee...))
    end
    for child in node.children
        _walk_inference!(edges, child)
    end
    return edges
end

"""
    _extract_inference_edges(root) -> Vector{Tuple{String,String,Int,String,String,Int}}

Extract caller→callee edges from an @snoop_inference tree. Each entry is
(caller_name, caller_file, caller_line, callee_name, callee_file, callee_line).
The inference-layer parser maps callee_file:line → content unit → test item.
"""
function _extract_inference_edges(root)
    edges = Tuple{String,String,Int,String,String,Int}[]
    isdefined(root, :ci) || return edges
    _walk_inference!(edges, root)
    return edges
end

# ── Read environment ──────────────────────────

test_file = get(ENV, "TESTIMONIAL_FILE", nothing)
test_item = get(ENV, "TESTIMONIAL_ITEM", nothing)
test_items_raw = get(ENV, "TESTIMONIAL_ITEMS", nothing)

if test_file === nothing
    println(stderr, "driver.jl: missing TESTIMONIAL_FILE")
    exit(3)
end

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

# ── Run the test(s) under @snoop_inference ────
# Wrap test execution with SnoopCompile's @snoop_inference to capture
# the inferred call graph alongside --code-coverage. The resulting
# caller→callee edges are serialized to `inference_trace.jls` in pwd,
# a sidecar consumed by the inference-layer parser (testimonial-be7o).

trace_path = joinpath(pwd(), "inference_trace.jls")

try
    root = SnoopCompile.@snoop_inference begin
        for item in item_names
            ReTestItems.runtests(test_file; name=item)
        end
    end
    edges = _extract_inference_edges(root)
    Serialization.serialize(trace_path, edges)
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