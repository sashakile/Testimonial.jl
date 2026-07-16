# Index builder — builds and maintains the coverage index from per-item records.
#
# Provides the public API for single-item and bulk recording, index
# construction, and cache management.
#
# See REC-005 through REC-008 in
# openspec/changes/implement-coverage-layer/specs/recording/spec.md

module IndexBuilder

using SHA

"""
    _record_single_item(test_file::AbstractString, item_name::AbstractString) -> Union{ItemCoverage, Nothing}

Record coverage for a single @testitem identified by its file and name.

Returns an `ItemCoverage` with the item's coverage data, or `nothing`
if the item is not found in the file.

This is a convenience API for single-item debugging. Called by
`Testimonial.record_item` in the parent module.

For bulk recording with caching and parallelism, use `record_all`.
"""
function _record_single_item(test_file::AbstractString, item_name::AbstractString)
    # Resolve the test file path
    abs_file = abspath(String(test_file))
    if !isfile(abs_file)
        throw(SystemError("test file not found: $(abs_file)"))
    end

    # Read the file and find the matching @testitem
    content = try
        read(abs_file, String)
    catch
        throw(SystemError("cannot read test file: $(abs_file)"))
    end

    # Use the parent module's helpers for discovery
    parent = Base.parentmodule(@__MODULE__)
    pattern = parent._TESTITEM_PATTERN
    tags = parent._parse_tags(content)
    fhash = bytes2hex(sha256(content))[1:12]

    # Find the matching @testitem
    found = false
    ref = nothing
    for m in eachmatch(pattern, content)
        name = m.captures[1]
        if name == item_name
            offset = m.offset
            line = count(==('\n'), content[1:offset]) + 1
            item_tags = get(tags, name, Symbol[])
            ref = parent.TestItemRef(abs_file, line, name, item_tags, fhash)
            found = true
            break
        end
    end

    if !found
        return nothing
    end

    # Record coverage using CoverageLayer
    return parent.record_item(ref)
end

end # module IndexBuilder