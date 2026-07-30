#!/usr/bin/env julia
# SPDX-License-Identifier: MIT
#
# stress_test.jl — Stress-test Testimonial.jl against real Julia codebases
#
# Clones N real Julia repos (with @testitem usage), runs the full discovery
# and query pipeline, and reports:
#   - Discovery: how many @testitems found
#   - Recording: time, success rate (uses MockRunner for speed)
#   - Index: size, schema version
#   - Source coverage: fraction of source files that produce test selections
#   - Test coverage: fraction of test items reachable via query
#   - Performance: per-step timing
#
# Usage:
#   julia --project scripts/stress_test.jl [--repos N] [--samples N] [--items N]
#
# Options:
#   --repos N    Max repos to test (default: all)
#   --samples N  Source files to sample per repo (default: 0 = all)
#   --items N    Max test items to record per repo (default: 0 = all, clipped to 50 for speed)
#   --output PATH  Output directory for results (default: .testimonial/stress/)
#
# Exit codes:
#   0 — All tests completed
#   1 — Setup or runtime error
#
# Requires: git, internet access to clone repos

using Testimonial
using Testimonial.Protocol
using Test
using Dates
using JSON
using Serialization
using SHA
using Statistics

# Load test helpers for MockRunner (fast, pipeline-only recording)
include(joinpath(@__DIR__, "..", "test", "helpers.jl"))

# ── Configuration ──────────────────────────────

const DEFAULT_REPOS = [
    ("sashakile", "Testimonial.jl", "Testimonial.jl — test impact analysis"),
    ("JuliaTesting", "ReTestItems.jl", "ReTestItems — test framework with @testitem"),
    ("JuliaTesting", "TestRecording.jl", "TestRecording — ReTestItems companion"),
]

struct StressConfig
    max_repos::Int
    max_items::Int  # 0 = all items (clipped to 50 for speed)
    sample_count::Int  # 0 = all source files
    output_dir::String
end

function parse_config()::StressConfig
    max_repos = length(DEFAULT_REPOS)
    max_items = 50
    samples = 0
    output = joinpath(".testimonial", "stress")

    i = 1
    while i <= length(ARGS)
        if ARGS[i] == "--repos" && i < length(ARGS)
            max_repos = parse(Int, ARGS[i+1])
            i += 2
        elseif ARGS[i] == "--items" && i < length(ARGS)
            max_items = parse(Int, ARGS[i+1])
            i += 2
        elseif ARGS[i] == "--samples" && i < length(ARGS)
            samples = parse(Int, ARGS[i+1])
            i += 2
        elseif ARGS[i] == "--output" && i < length(ARGS)
            output = ARGS[i+1]
            i += 2
        else
            @warn "Unknown argument: $(ARGS[i])"
            i += 1
        end
    end

    return StressConfig(max_repos, max_items, samples, output)
end

# ── Helpers ────────────────────────────────────

"""Clone a GitHub repo to target dir. Returns true if successful."""
function clone_repo(org::String, name::String, target::String)::Bool
    if isdir(target)
        @info "  Repo already exists at $(target), pulling..."
        try
            cd(target) do
                run(`git pull --ff-only`)
            end
            return true
        catch e
            @warn "  Could not pull $(name): $e"
            return false
        end
    end

    url = "https://github.com/$(org)/$(name).git"
    @info "  Cloning $(url)..."
    try
        run(`git clone --depth=1 $(url) $(target)`)
        return true
    catch e
        @warn "  Could not clone $(name): $e"
        return false
    end
end

"""Find all .jl source files in src/ directory, excluding package.jl."""
function find_source_files(repo_dir::String)::Vector{String}
    src_dir = joinpath(repo_dir, "src")
    if !isdir(src_dir)
        return String[]
    end
    files = String[]
    for (root, _, filenames) in walkdir(src_dir)
        for f in filenames
            if endswith(f, ".jl")
                push!(files, joinpath(root, f))
            end
        end
    end
    return sort(files)
end

"""Find all .jl test files in test/ directory."""
function find_test_files(repo_dir::String)::Vector{String}
    test_dir = joinpath(repo_dir, "test")
    if !isdir(test_dir)
        return String[]
    end
    files = String[]
    for (root, _, filenames) in walkdir(test_dir)
        for f in filenames
            if endswith(f, ".jl")
                push!(files, joinpath(root, f))
            end
        end
    end
    return sort(files)
end

"""Check if a test file contains @testitem blocks."""
function has_testitems(file::String)::Bool
    try
        content = read(file, String)
        return occursin(r"@testitem\b", content)
    catch
        return false
    end
end

"""Run discovery on a repo directory. Returns discovered items or empty."""
function discover_items(repo_dir::String, config::StressConfig)::Vector{Testimonial.TestItemRef}
    test_dir = joinpath(repo_dir, "test")
    if !isdir(test_dir)
        @warn "  No test/ directory found"
        return Testimonial.TestItemRef[]
    end

    try
        cd(repo_dir) do
            items = Testimonial.discover_testitems([test_dir])
            @info "  Discovered $(length(items)) @testitem(s)"
            return items
        end
    catch e
        @warn "  Discovery failed: $e"
        return Testimonial.TestItemRef[]
    end
end

"""Record coverage for all items. Returns (index, elapsed_seconds)."""
function record_items(items::Vector{Testimonial.TestItemRef}, repo_dir::String, config::StressConfig)
    if isempty(items)
        return nothing, 0.0
    end

    runner = MockRunner()

    # Limit items for speed
    record_items = items
    if config.max_items > 0 && length(items) > config.max_items
        record_items = items[1:config.max_items]
        @info "  Limiting to $(config.max_items) items for recording"
    end

    start_time = time_ns()
    index = try
        cd(repo_dir) do
            Testimonial.record_all(record_items, runner; force=true)
        end
    catch e
        @warn "  Recording failed: $e"
        return nothing, 0.0
    end
    elapsed = (time_ns() - start_time) / 1e9

    return index, elapsed
end

"""Build index from cache. Returns (index, elapsed_seconds)."""
function build_index_from_cache(repo_dir::String)::Tuple{Union{Nothing, Testimonial.CoverageIndex}, Float64}
    testimonial_dir = joinpath(repo_dir, ".testimonial")
    items_dir = joinpath(testimonial_dir, "items")

    if !isdir(items_dir)
        return nothing, 0.0
    end

    start_time = time_ns()
    index = try
        cd(repo_dir) do
            Testimonial.build_index(items_dir)
        end
    catch e
        @warn "  Index build failed: $e"
        return nothing, 0.0
    end
    elapsed = (time_ns() - start_time) / 1e9

    return index, elapsed
end

"""Sample source files from the repo. Returns relative paths."""
function sample_source_files(repo_dir::String, config::StressConfig)::Vector{String}
    src_dir = joinpath(repo_dir, "src")
    if !isdir(src_dir)
        return String[]
    end

    files = String[]
    for (root, _, filenames) in walkdir(src_dir)
        for f in filenames
            if endswith(f, ".jl") && f != "$(basename(repo_dir)).jl"
                rel = relpath(joinpath(root, f), repo_dir)
                push!(files, rel)
            end
        end
    end

    if config.sample_count > 0 && length(files) > config.sample_count
        files = sample(files, config.sample_count, replace=false)
    end

    return sort(files)
end

"""Run query for each source file and measure source coverage.

Returns (source_coverage_pct, test_coverage_pct, query_time_seconds, details).
"""
function measure_query_coverage(
    index::Testimonial.CoverageIndex,
    source_files::Vector{String},
    repo_dir::String,
)::Tuple{Float64, Float64, Float64, Vector{Dict}}
    isempty(source_files) && return (0.0, 0.0, 0.0, Dict{String, Any}[])
    isempty(index.items) && return (0.0, 0.0, 0.0, Dict{String, Any}[])

    total_sources = length(source_files)
    sources_with_edges = 0
    all_selected_items = Set{String}()
    details = Dict{String, Any}[]

    # Build providers list
    providers = [
        Testimonial.direct_change_provider,
        Testimonial.unresolved_provider,
        Testimonial.inference_provider,
        Testimonial.static_provider,
        Testimonial.runtime_edge_provider,
    ]

    query_start = time_ns()

    for src_file in source_files
        # Simulate a change: mark a few lines as changed
        changed = Dict{String, Set{Int}}(
            src_file => Set([1, 2, 3]),  # dummy line numbers
        )

        results = Testimonial.query(providers, index, changed)
        selected = [r for r in results if r.selected]

        edge_count = length(selected)
        if edge_count > 0
            sources_with_edges += 1
            for r in selected
                push!(all_selected_items, "$(r.item.file):$(r.item.name)")
            end
        end

        push!(details, Dict{String, Any}(
            "file" => src_file,
            "edges" => edge_count,
            "selected_items" => [string(r.item.name) for r in selected],
        ))
    end

    query_elapsed = (time_ns() - query_start) / 1e9

    source_coverage = total_sources > 0 ? (sources_with_edges / total_sources) * 100.0 : 0.0
    test_coverage = length(index.items) > 0 ? (length(all_selected_items) / length(index.items)) * 100.0 : 0.0

    return (source_coverage, test_coverage, query_elapsed, details)
end

"""Measure index size in bytes."""
function index_size(repo_dir::String)::Int
    testimonial_dir = joinpath(repo_dir, ".testimonial")
    if !isdir(testimonial_dir)
        return 0
    end
    total = 0
    for (root, _, files) in walkdir(testimonial_dir)
        for f in files
            fp = joinpath(root, f)
            total += stat(fp).size
        end
    end
    return total
end

"""Format a duration in seconds to a human-readable string."""
function format_duration(seconds::Float64)::String
    if seconds < 1.0
        return "$(round(seconds * 1000, digits=1)) ms"
    elseif seconds < 60.0
        return "$(round(seconds, digits=2)) s"
    else
        m = floor(Int, seconds / 60)
        s = round(seconds - m * 60, digits=1)
        return "$(m)m $(s)s"
    end
end

# ── Report ─────────────────────────────────────

struct RepoResult
    name::String
    org::String
    description::String
    status::String  # :ok, :skipped, :failed
    file_count::Int
    test_file_count::Int
    testitem_count::Int
    source_files::Int
    has_testitems::Bool
    discovery_time::Float64
    recording_time::Float64
    index_time::Float64
    index_size_bytes::Int
    index_item_count::Int
    source_coverage_pct::Float64
    test_coverage_pct::Float64
    query_time::Float64
    errors::Vector{String}
end

function print_report(results::Vector{RepoResult}, config::StressConfig)::Nothing
    println("\n" * "="^70)
    println("  TESTIMONIAL.JL STRESS TEST REPORT")
    println("  Mode: mock (pipeline)  |  Items: $(config.max_items > 0 ? config.max_items : "all")  |  Samples: $(config.sample_count > 0 ? config.sample_count : "all")")
    println("  Date: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
    println("  Julia: $(VERSION)  |  Threads: $(Threads.nthreads())")
    println("="^70)

    print("\n")
    for r in results
        status_icon = r.status == "ok" ? "✓" : (r.status == "skipped" ? "○" : "✗")
        println("  $(status_icon) $(r.org)/$(r.name)")
        println("     $(r.description)")
        if r.status != "ok"
            println("     Status: $(r.status)")
            for e in r.errors
                println("     Error: $e")
            end
            println()
            continue
        end
        println("     Files:      $(r.file_count) source, $(r.test_file_count) test ($(r.testitem_count) @testitems)")
        println("     Sources:    $(r.source_files) sampled")
        println("     Discovery:  $(format_duration(r.discovery_time))")
        println("     Recording:  $(format_duration(r.recording_time))  ($(r.index_item_count) items)")
        println("     Index:      $(format_duration(r.index_time))  ($(format_bytes(r.index_size_bytes)))")
        println("     Query:      $(format_duration(r.query_time))")
        println("     Coverage:   $(round(r.source_coverage_pct, digits=1))% source files → $(round(r.test_coverage_pct, digits=1))% test items")
        println()
    end

    # Summary
    ok_count = count(r -> r.status == "ok", results)
    skip_count = count(r -> r.status == "skipped", results)
    fail_count = count(r -> r.status == "failed", results)

    println("  ─" * repeat("-", 50))
    println("  Summary: $(ok_count) passed, $(skip_count) skipped, $(fail_count) failed")

    if ok_count > 0
        avg_source_cov = mean([r.source_coverage_pct for r in results if r.status == "ok"])
        avg_test_cov = mean([r.test_coverage_pct for r in results if r.status == "ok"])
        avg_recording = mean([r.recording_time for r in results if r.status == "ok" && r.recording_time > 0])
        avg_query = mean([r.query_time for r in results if r.status == "ok" && r.query_time > 0])

        println("  Average source coverage:  $(round(avg_source_cov, digits=1))%")
        println("  Average test coverage:    $(round(avg_test_cov, digits=1))%")
        println("  Average recording time:   $(format_duration(avg_recording))")
        println("  Average query time:       $(format_duration(avg_query))")
    end
    println("="^70)

    return nothing
end

function format_bytes(bytes::Int)::String
    if bytes < 1024
        return "$bytes B"
    elseif bytes < 1024^2
        return "$(round(bytes / 1024, digits=1)) KB"
    else
        return "$(round(bytes / 1024^2, digits=1)) MB"
    end
end

function save_results_json(results::Vector{RepoResult}, config::StressConfig)::Nothing
    mkpath(config.output_dir)
    json_path = joinpath(config.output_dir, "stress_test_$(Dates.format(now(), "yyyy-mm-dd-HH-MM-SS")).json")

    json_results = [Dict{String, Any}(
        "name" => r.name,
        "org" => r.org,
        "description" => r.description,
        "status" => r.status,
        "file_count" => r.file_count,
        "test_file_count" => r.test_file_count,
        "testitem_count" => r.testitem_count,
        "source_files" => r.source_files,
        "has_testitems" => r.has_testitems,
        "discovery_time_s" => r.discovery_time,
        "recording_time_s" => r.recording_time,
        "index_time_s" => r.index_time,
        "index_size_bytes" => r.index_size_bytes,
        "index_item_count" => r.index_item_count,
        "source_coverage_pct" => r.source_coverage_pct,
        "test_coverage_pct" => r.test_coverage_pct,
        "query_time_s" => r.query_time,
        "errors" => r.errors,
    ) for r in results]

    report = Dict{String, Any}(
        "timestamp" => string(now()),
        "julia_version" => string(VERSION),
        "threads" => Threads.nthreads(),
        "sample_count" => config.sample_count,
        "results" => json_results,
    )

    open(json_path, "w") do io
        println(io, JSON.json(report, 2))
    end

    @info "Results saved to $(json_path)"
    return nothing
end

# ── Main ───────────────────────────────────────

function main()::Int
    config = parse_config()
    @info "Starting stress test (max_repos=$(config.max_repos))"

    # Create scratch dir for repos
    scratch_dir = mktempdir(; prefix="testimonial-stress-")
    @info "Scratch directory: $(scratch_dir)"

    repos_to_test = DEFAULT_REPOS[1:min(config.max_repos, end)]
    results = RepoResult[]

    for (org, name, description) in repos_to_test
        println("\n" * "─"^70)
        println("  Testing: $(org)/$(name)")
        println("  $(description)")
        println("─"^70)

        repo_dir = joinpath(scratch_dir, name)
        errors = String[]

        # Step 1: Clone
        if !clone_repo(org, name, repo_dir)
            push!(errors, "Clone failed")
            push!(results, RepoResult(name, org, description, "failed", 0, 0, 0, 0, false, 0.0, 0.0, 0.0, 0, 0, 0.0, 0.0, 0.0, errors))
            continue
        end

        # Step 2: Count files
        source_files_list = find_source_files(repo_dir)
        test_files = find_test_files(repo_dir)
        test_files_with_items = filter(f -> has_testitems(f), test_files)
        file_count = length(source_files_list)
        test_file_count = length(test_files_with_items)

        if isempty(test_files_with_items)
            @info "  No @testitem files found — skipping"
            push!(results, RepoResult(name, org, description, "skipped", file_count, length(test_files), 0, 0, false, 0.0, 0.0, 0.0, 0, 0, 0.0, 0.0, 0.0, errors))
            continue
        end

        # Step 3: Discover
        disc_start = time_ns()
        items = discover_items(repo_dir, config)
        disc_time = (time_ns() - disc_start) / 1e9

        if isempty(items)
            @info "  No @testitems discovered — skipping"
            push!(results, RepoResult(name, org, description, "skipped", file_count, length(test_files_with_items), 0, 0, true, disc_time, 0.0, 0.0, 0, 0, 0.0, 0.0, 0.0, errors))
            continue
        end

        # Step 4: Record
        index, rec_time = record_items(items, repo_dir, config)

        if index === nothing
            push!(errors, "Recording failed")
            push!(results, RepoResult(name, org, description, "failed", file_count, length(test_files_with_items), length(items), 0, true, disc_time, 0.0, 0.0, 0, 0, 0.0, 0.0, 0.0, errors))
            continue
        end

        # Step 5: Build index from cache
        _, idx_time = build_index_from_cache(repo_dir)

        # Step 6: Measure index size
        idx_size = index_size(repo_dir)

        # Step 7: Sample source files and measure query coverage
        source_samples = sample_source_files(repo_dir, config)
        source_cov, test_cov, query_time, _ = measure_query_coverage(index, source_samples, repo_dir)

        push!(results, RepoResult(
            name, org, description, "ok",
            file_count, length(test_files_with_items), length(items),
            length(source_samples), true,
            disc_time, rec_time, idx_time, idx_size, length(index.items),
            source_cov, test_cov, query_time, errors,
        ))

        @info "  ✓ $(name): $(length(items)) items, $(round(source_cov, digits=1))% source coverage"
    end

    # Print report
    print_report(results, config)

    # Save JSON
    save_results_json(results, config)

    # Cleanup
    @info "Cleaning up scratch directory..."
    try
        rm(scratch_dir; recursive=true, force=true)
    catch
    end

    return 0
end

# ── Entry point ────────────────────────────────

exit(main())