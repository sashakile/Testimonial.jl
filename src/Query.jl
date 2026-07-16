# Query engine — determines which @testitems are affected by changed files.
#
# Given a CoverageIndex and a list of changed files (from git diff or
# testaruda protocol), the query engine returns ImpactResults that identify
# which test items should be re-run and why.
#
# See SEL-002 through SEL-005 in
# openspec/changes/implement-coverage-layer/specs/smart-selection/spec.md

module Query

export query_files

"""
    query_files(index, files) -> Vector{ImpactResult}

Given a CoverageIndex and a list of changed file paths, return ImpactResults
for all test items that are affected by the changes.

For each file:
- If the file is a test file tracked in the index, all items in that file
  get a `DirectChange` reason and `selected = true`.
- If the file is not tracked in the index (source file, config file, etc.),
  the result is `Unresolved` — meaning the system cannot determine which
  tests to run and should fall back to running all tests.

Results are deduplicated: if multiple changed files affect the same test
item, the item appears once with all reasons accumulated.

# Examples
```julia
result = query_files(index, [\"test/foo_test.jl\", \"src/bar.jl\"])
for r in result
    if r.selected
        println(\"Run \$(r.item.name): \$(r.reasons)\")
    end
end
```
"""
function query_files(index, files::Vector{String})::Vector
    parent = Base.parentmodule(@__MODULE__)
    isempty(files) && return parent.ImpactResult[]

    # Build a reverse index: file_path → [TestItemRef, ...]
    file_to_items = Dict{String, Vector{parent.TestItemRef}}()
    for (ref, _) in index.items
        f = ref.file
        if !haskey(file_to_items, f)
            file_to_items[f] = parent.TestItemRef[]
        end
        push!(file_to_items[f], ref)
    end

    seen = Set{Pair{String, String}}()  # (file, name) dedup key
    results = parent.ImpactResult[]

    for file in files
        # Normalize the path for lookup
        norm_file = isabspath(file) ? file : abspath(file)

        if haskey(file_to_items, norm_file)
            # Test file tracked in the index — all items are directly affected
            for ref in file_to_items[norm_file]
                key = ref.file => ref.name
                if key in seen
                    continue
                end
                push!(seen, key)

                reason = parent.ImpactReason(parent.DirectChange, "file changed: $(norm_file)")
                push!(results, parent.ImpactResult(ref, [reason], true))
            end
        else
            # File not tracked in the index — unresolved
            # We emit a single Unresolved result to signal the caller
            # should fall back to running all tests.
            ref = parent.TestItemRef(norm_file, 0, "")
            reason = parent.ImpactReason(parent.Unresolved, "file not tracked in coverage index: $(norm_file)")
            push!(results, parent.ImpactResult(ref, [reason], false))
        end
    end

    return results
end

end # module Query