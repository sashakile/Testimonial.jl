# Git diff parser — parses unified git diff output into file→changed lines maps.
#
# The parser tracks only additions/modifications (`+` lines) and resolves
# relative paths to absolute form. Only `.jl` and `.toml` files are included
# in the result — non-code files like Markdown, images, etc. are excluded.
#
# See SEL-001 in openspec/changes/implement-coverage-layer/specs/smart-selection/spec.md

module GitDiff

export parse_unified_diff

"""
    parse_unified_diff(diff_text::AbstractString, repo_root::AbstractString) -> Dict{String, Set{Int}}

Parse a unified git diff string and return a map of absolute file paths to
sets of changed (added/modified) line numbers.

Only lines prefixed with `+` (additions) are counted. Deletions (`-`) and
context lines (space-prefixed or blank) are ignored. Only `.jl` and `.toml`
files are included in the result.

Paths in the diff are resolved relative to `repo_root` and normalized to
absolute form. Deleted files are included with an empty set of changed
lines so the selection engine can detect them. Renamed files produce two
entries: the new path (with any changed lines) and the old path (empty)
for edge provider matching. New files have all their added lines included.
Binary files are skipped.
"""
function parse_unified_diff(diff_text::AbstractString, repo_root::AbstractString)::Dict{String, Set{Int}}
    result = Dict{String, Set{Int}}()
    isempty(strip(diff_text)) && return result

    # Split into per-file diff sections by "diff --git " headers
    sections = split(diff_text, "\ndiff --git "; keepempty=false)
    # If the first section doesn't start with "diff --git " (because we split on it),
    # check if it's empty or a preamble
    for section in sections
        content = startswith(section, "diff --git ") ? section : "diff --git $section"
        _parse_diff_section(content, repo_root, result)
    end

    return result
end

"""Parse a single "diff --git ..." section and update `result` in-place."""
function _parse_diff_section(section::AbstractString, repo_root::AbstractString, result::Dict)
    lines = split(section, '\n'; keepempty=false)
    isempty(lines) && return

    # --- Extract file paths from diff --git header ---
    first_line = lines[1]
    if !startswith(first_line, "diff --git ")
        return
    end

    # Extract a/ and b/ paths from "diff --git a/path b/path"
    path_part = strip(first_line[12:end])  # after "diff --git "
    a_b_paths = split(path_part)
    length(a_b_paths) != 2 && return

    a_path = _strip_prefix(a_b_paths[1])  # strip "a/"
    b_path = _strip_prefix(a_b_paths[2])  # strip "b/"

    # --- Detect file operation type ---
    is_deleted = false
    is_new = false
    is_renamed = false
    new_name = nothing
    old_name = nothing

    # Check for mode/rename lines before ---/+++
    body_start = 2
    for (i, line) in enumerate(lines[2:end])
        idx = i + 1
        if startswith(line, "deleted file mode")
            is_deleted = true
            body_start = idx + 1
        elseif startswith(line, "new file mode")
            is_new = true
            body_start = idx + 1
        elseif startswith(line, "rename from ")
            is_renamed = true
            old_name = strip(line[12:end])
            body_start = idx + 1
        elseif startswith(line, "rename to ")
            new_name = strip(line[10:end])
            body_start = idx + 1
        elseif startswith(line, "--- ")
            body_start = idx
            break
        elseif startswith(line, "Binary files ")
            return  # skip binary files entirely
        elseif startswith(line, "index ")
            continue
        elseif startswith(line, "similarity index")
            continue
        else
            break  # unknown header line — stop scanning
        end
    end

    # --- Determine effective file path ---
    if is_deleted
        # Deleted files are included so edge providers can find old paths
        old_abs = _resolve_path(a_path, repo_root)
        if endswith(old_abs, ".jl") || endswith(old_abs, ".toml")
            result[old_abs] = Set{Int}()
        end
        return
    end

    # For renamed files, use the new name
    file_path = if is_renamed && new_name !== nothing
        new_name
    elseif b_path == "/dev/null"
        return  # nothing to track
    else
        b_path
    end

    # Filter to .jl and .toml files only.
    # For renames from .jl/.toml to a non-tracked type, still add the old path
    # so edge providers can find historical references.
    if !(endswith(file_path, ".jl") || endswith(file_path, ".toml"))
        if is_renamed && old_name !== nothing &&
           (endswith(old_name, ".jl") || endswith(old_name, ".toml"))
            old_abs = _resolve_path(old_name, repo_root)
            result[old_abs] = Set{Int}()
        end
        return
    end

    # Resolve to absolute path
    abs_path = _resolve_path(file_path, repo_root)

    # --- Parse hunks ---
    changed_lines = Set{Int}()

    i = body_start
    while i <= length(lines)
        line = lines[i]
        if startswith(line, "@@ ")
            # Parse hunk header: @@ -old_start,old_count +new_start,new_count @@
            nline_start = _parse_new_start(line)
            if nline_start === nothing
                i += 1
                continue
            end

            # Track line number in the NEW file as we process hunk lines
            new_line_num = nline_start
            i += 1

            while i <= length(lines)
                hunk_line = lines[i]
                if startswith(hunk_line, "@@ ")
                    # Next hunk — stop and let outer loop handle it
                    break
                elseif startswith(hunk_line, "diff --git ")
                    # Next file section — stop entirely
                    break
                elseif startswith(hunk_line, "\\ No newline")
                    # Trailing no-newline marker — skip, no line number change
                    i += 1
                    continue
                elseif startswith(hunk_line, "+")
                    # Added/modified line — record the line number
                    push!(changed_lines, new_line_num)
                    new_line_num += 1
                elseif startswith(hunk_line, "-")
                    # Deleted line — no new file line, just skip
                    i += 1
                    continue
                else
                    # Context line (space-prefixed or blank) — increments new file count
                    new_line_num += 1
                end
                i += 1
            end
        else
            i += 1
        end
    end

    # Always add the file to the result, even with no changed lines.
    # This ensures deleted-only hunks, pure renames, and other edge cases
    # produce a non-empty changed_files so the selection engine doesn't
    # see "no relevant change" and run no tests.
    result[abs_path] = changed_lines

    # For renames, also add the old path with empty lines so edge providers
    # can match against historical source file references.
    if is_renamed && old_name !== nothing
        old_abs = _resolve_path(old_name, repo_root)
        if !haskey(result, old_abs)
            result[old_abs] = Set{Int}()
        end
    end
end

"""Strip `a/` or `b/` prefix from a git diff path."""
function _strip_prefix(path::AbstractString)::String
    if length(path) >= 2 && (startswith(path, "a/") || startswith(path, "b/"))
        return path[3:end]
    end
    return String(path)
end

"""Parse the new-file start line number from a hunk header."""
function _parse_new_start(hunk_header::AbstractString)::Union{Int, Nothing}
    # Format: @@ -old_start,old_count +new_start,new_count @@[ optional context]
    # Find the +num or +num,num portion
    plus_idx = findfirst('+', hunk_header)
    plus_idx === nothing && return nothing

    after_plus = hunk_header[plus_idx+1:end]
    # Find the end of the new-start number (stop at ',' or space or '@@')
    end_idx = findfirst(c -> c in (',', ' ', '@'), after_plus)
    num_str = if end_idx === nothing
        strip(after_plus)
    else
        after_plus[1:end_idx-1]
    end

    if isempty(num_str)
        return nothing
    end

    try
        return parse(Int, num_str)
    catch
        return nothing
    end
end

"""Resolve a diff-relative path to an absolute path using `repo_root`."""
function _resolve_path(rel_path::AbstractString, repo_root::AbstractString)::String
    joined = joinpath(repo_root, rel_path)
    try
        return realpath(joined)
    catch
        # If the file doesn't exist (e.g., new file not yet created),
        # return the normalized absolute path without realpath
        return abspath(joined)
    end
end

end # module GitDiff