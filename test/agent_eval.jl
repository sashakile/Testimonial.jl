# Agent Behavior Self-Eval (just agent-check)
#
# This eval suite tests whether AGENTS.md is properly structured with the
# required governance artifacts. It is NOT a product test suite.
#
# Usage:
#   just agent-check         # Run full agent behavior eval suite

using Test

pass_count = 0
fail_count = 0
total = 0

function check(description, condition)
    global total, pass_count, fail_count
    total += 1
    if condition
        pass_count += 1
        println("[PASS] $description")
    else
        fail_count += 1
        println("[FAIL] $description")
    end
end

path = joinpath(@__DIR__, "..", "AGENTS.md")
content = read(path, String)

# Flatten the file: join lines that are continuations (blockquote or wrapped)
# so multi-line patterns can be found. A line starting with ">" or a line
# that is clearly a continuation (no blank line above) is glued together.
flat = replace(content, r"\n> " => " ")
flat = replace(flat, r"\n(?!\n|#|<!--)" => " ", count=20)  # basic collapse

# ── Goal Sandwich ──────────────────────────────────
check("PRIMARY OBJECTIVE in first 1000 chars",
      occursin("PRIMARY OBJECTIVE", content[1:min(1000, length(content))]))
check("PRIMARY OBJECTIVE in last 1000 chars",
      occursin("PRIMARY OBJECTIVE", content[max(1, length(content)-1000):end]))

# VP check: both top and bottom should contain the full VP sentence
vp_fragment = "Testimonial is a Julia-native"
check("VP in top third of file",
      occursin(vp_fragment, content[1:min(4000, length(content))]))
check("VP in bottom third of file",
      occursin(vp_fragment, content[max(1, length(content)-4000):end]))

# ── PROHIBITED ACTIONS ────────────────────────────
check("PROHIBITED ACTIONS section exists", occursin("PROHIBITED ACTIONS", content))

# Count "Never" lines by looking for lines starting with - **Never
never_lines = filter(l -> occursin(r"^- \*\*Never", l), split(content, "\n"))
never_count = length(never_lines)
check("At least 5 PROHIBITED ACTIONS (Never rules)", never_count >= 5)

# ── Behavioral Principles ─────────────────────────
check("Proportionality principle exists", occursin("Proportionality", content))
check("Verifiability principle exists", occursin("Verifiability", content))
check("Corrigibility principle exists", occursin("Corrigibility", content))

# ── Escalation Triggers ───────────────────────────
check("Escalation Triggers section exists", occursin("Escalation Triggers", content))
triggers = ["Ambiguity", "Scope uncertainty", "Irreversibility",
            "Unexpected state", "Conflicting instructions", "High stakes",
            "Confidence below threshold"]
found = sum([occursin(t, content) for t in triggers])
check("All 7 escalation triggers present", found >= 7)
check("2× tool failure escalation present",
      occursin("tool call fails 2×", content))

# ── TDD / Ro5 ─────────────────────────────────────
check("TDD pipeline instructions exist",
      occursin("failing test first", content))
check("Ro5 review mentioned",
      occursin("`/ro5` after", content))

# ── Context discipline ────────────────────────────
check("Context threshold at ~40%",
      occursin("context reaches ~40%", content))
check("Stop and tell user on context saturation",
      occursin("stop and tell the user", content))

# ── Summary ───────────────────────────────────────
println("\n==========================")
println("Agent Behavior Eval Suite")
println("==========================")
println("Passed: $pass_count/$total")
println("Failed: $fail_count/$total")
println("==========================")

exit(fail_count > 0 ? 1 : 0)