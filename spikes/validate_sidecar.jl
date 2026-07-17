#!/usr/bin/env julia
# SPDX-License-Identifier: MIT
#
# Spike: Validate coverage sidecar attribution.
# Focused test: does Coverage.process_file correctly attribute hits
# from .jl.cov files? Does it work across symlinks?
#
# The subprocess runner will create a proper package and exercise it
# with --code-coverage=user to generate real .jl.cov files.

using Coverage, Test

mktempdir() do root
    # ── 1. Create a proper Julia package ─────
    write(joinpath(root, "Project.toml"), """
    name = "TestPkg"
    uuid = "a0000000-0000-0000-0000-000000000001"
    version = "0.1.0"
    """)
    src_dir = joinpath(root, "src")
    mkpath(src_dir)
    src_file = joinpath(src_dir, "TestPkg.jl")
    write(src_file, """
    module TestPkg
        function covered_func(x)
            return x + 1
        end
        function uncovered_func()
            return 42
        end
        export covered_func
    end
    """)

    # Runner script that uses the package
    run_file = joinpath(root, "run.jl")
    write(run_file, """
    using TestPkg
    println(TestPkg.covered_func(5))
    """)

    # ── 2. Run as proper package ───────────
    # This mimics how the driver.jl subprocess works
    cd(root) do
        run(`julia --code-coverage=user --project=$(root) -e 'include("run.jl")'`)
    end

    # ── 3. Find .jl.cov files ──────────────
    cov_files = String[]
    for (d, dirs, files) in walkdir(root)
        for f in files
            endswith(f, ".jl.cov") && push!(cov_files, joinpath(d, f))
        end
    end

    println("═══ Results ═══")
    println(".jl.cov files: $(length(cov_files))")
    for cf in sort(cov_files)
        real = try realpath(cf) catch cf end
        println("  $(cf)")
        println("    realpath → $(real)")
    end

    # ── 4. Parse coverage ──────────────────
    if isfile(src_file * ".cov")
        fc = Coverage.process_file(src_file, src_dir)
        println("\nCoverage from original path:")
        for (i, c) in enumerate(fc.coverage)
            if c !== nothing
                println("  Line $i: count=$c")
            end
        end
    end

    # ── 5. Test symlinked variant ──────────
    shadow = joinpath(root, "shadow", "src")
    mkpath(shadow)
    symlink(src_file, joinpath(shadow, "TestPkg.jl"))

    write(joinpath(dirname(shadow), "Project.toml"), read(joinpath(root, "Project.toml"), String))
    write(joinpath(dirname(shadow), "run.jl"), "using TestPkg\nprintln(TestPkg.covered_func(10))")

    cd(dirname(shadow)) do
        run(`julia --code-coverage=user --project=$(dirname(shadow)) -e 'include("run.jl")'`)
    end

    cov_files2 = String[]
    for (d, dirs, files) in walkdir(root)
        for f in files
            endswith(f, ".jl.cov") && push!(cov_files2, joinpath(d, f))
        end
    end

    println("\n═══ After symlinked run ═══")
    println(".jl.cov files: $(length(cov_files2))")
    for cf in sort(setdiff(cov_files2, cov_files))
        real = try realpath(cf) catch cf end
        println("  NEW: $(cf)")
        println("    realpath → $(real)")
    end

    if isfile(src_file * ".cov")
        fc2 = Coverage.process_file(src_file, src_dir)
        println("\nCoverage after shadow run:")
        for (i, c) in enumerate(fc2.coverage)
            if c !== nothing && c > 0
                println("  ✓ Line $i: count=$c")
            end
        end

        # Validate: covered_func should have count>0, uncovered_func should not
        covered = count(c -> c !== nothing && c > 0, fc2.coverage)
        println("\nTotal covered: $covered / $(length(fc2.coverage)) executable lines")
        println("Expected: covered_func body (line ~5) should have count > 0")
        println("            uncovered_func body (line ~8) should be 0")
    end
end