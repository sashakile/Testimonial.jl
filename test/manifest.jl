# test/manifest.jl — canonical test file manifest
#
# Every test_*.jl in test/ must be classified as :quick or :slow.
# Adding a new test_*.jl without classification fails CI.
# Both runtests.jl and runtests_quick.jl derive their include lists
# from this manifest (see full_tests() and quick_tests() below).
#
# Convention:
#   :quick — fast tests (< 1s), no subprocess spawning. Run in CI.
#   :slow  — subprocess-heavy (record_item, protocol adapter, inference
#            capture). Run in full suite only.
#
# IMPORTANT: When adding a new test_*.jl, add it here FIRST. The CI
# completeness check will fail until it's classified.

const TEST_MANIFEST = Pair{String, Symbol}[]

"""
    check_manifest_completeness() -> NamedTuple

Enumerate all `test_*.jl` files in test/ and compare against the manifest.
Returns unclassified (in dir but not in manifest) and orphans (in manifest
but missing from dir). Callers should error on non-empty unclassified.
"""
function check_manifest_completeness()
    dir = @__DIR__
    classified = Set{String}(k for (k, _) in TEST_MANIFEST)
    actual = Set{String}()
    for f in readdir(dir)
        startswith(f, "test_") && endswith(f, ".jl") && push!(actual, f)
    end
    return (
        unclassified = collect(sort!(collect(setdiff(actual, classified)))),
        orphans = collect(sort!(collect(setdiff(classified, actual)))),
    )
end

"""
    full_tests() -> Vector{String}

All test files to include in the full suite (just test / Pkg.test).
Includes both :quick and :slow files in manifest order.
"""
function full_tests()
    return [k for (k, _) in TEST_MANIFEST]
end

"""
    quick_tests() -> Vector{String}

Test files that run in the quick suite (CI / just test-quick).
Only :quick-classified files.
"""
function quick_tests()
    return [k for (k, v) in TEST_MANIFEST if v == :quick]
end

"""
    slow_tests() -> Vector{String}

Test files classified as :slow (excluded from quick mode).
"""
function slow_tests()
    return [k for (k, v) in TEST_MANIFEST if v == :slow]
end