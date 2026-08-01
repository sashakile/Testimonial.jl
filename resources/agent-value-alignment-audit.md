# Agent Value Alignment Report

**Target:** pi coding assistant operating within the Testimonial.jl governance framework (beads, wai, espectacular, pretender)
**Scope note:** The target is the runtime agent (pi). The governance toolset (beads, wai, espectacular, pretender, AGENTS.md) is the infrastructure within which pi operates — findings about the toolset are labelled [toolset] vs [agent] to avoid conflating the two.
**Mode:** AUDIT
**Date:** 2026-08-01
**Reviewer:** pi (self-audit using agent-value-alignment skill — see Limitations § for self-audit bias)
**Sources consulted:** AGENTS.md, .wai/AGENTS.md, .beads/, justfile, README.md, pretender.toml, .espectacular/config.toml, test/manifest.jl, docs/src/architecture.md, whisper notes

---

### Executive Summary

The Testimonial.jl project has an unusually mature agent governance infrastructure for an open-source Julia project — beads issue tracking with TDD pipeline, wai decision tracking, espectacular spec-contract verification, a comprehensive AGENTS.md, and a justfile that gates quality. However, the loop is **not closed** between these components. The value proposition is implicit (no formal falsifiable statement), there is no agent-level eval suite to verify that agent behavior achieves outcomes (only output-correctness tests), and no traceability matrix links governance decisions → prompt clauses → eval tests.

**The most critical gap is Layer 3 (🔴 NOT_ALIGNED)** — no eval suite verifies agent behavior, making every AGENTS.md instruction unverifiable. The least developed layer is Layer 4 (🟡 PARTIAL) — no decay dashboard, no alignment-oriented checkpointing, no value realization review.

**Overall verdict:** NOT_ALIGNED (two layers NOT_ALIGNED/🔴, three layers PARTIAL/🟡)

### Positive Findings

The project has several strengths worth preserving and building on:

- **AGENTS.md (174 lines)** — a comprehensive, version-controlled agent instruction set that serves as a de facto system prompt. Most projects have no equivalent.
- **Beads issue tracker** — with TDD pipeline (RED→GREEN→REFACTOR per ticket), workflow hooks (`bd close`, `bd push`), and interaction history — providing excellent functional traceability.
- **Wai decision tracking** — research capture, decision records, and project state awareness across sessions.
- **Espectacular spec-contract verification** — `ah check` validates spec–test correspondence, catching drift between proposals and implementation.
- **Openspec change proposals** — structured proposal→design→tasks→archive workflow for every feature change, with validation gates.
- **Pretender quality gates** — pre-commit hooks running complexity, duplication, formatting, and style checks on every commit.
- **Justfile as gate central** — `just check`, `just test-quick`, `just docs-build`, `just ah-check` provide a unified quality checkpoint.

### Layer Scores

| Layer | Status | Findings count |
|---|---|---|
| 1 — Value | 🟡 PARTIAL | 3 (high) |
| 2 — Governance | 🟡 PARTIAL | 2 (medium) |
| 3 — Runtime Prompt | 🔴 NOT_ALIGNED | 1 critical, 2 high, 1 medium |
| 4 — Infrastructure | 🟡 PARTIAL | 1 high, 1 medium |
| Integration | 🔴 NOT_ALIGNED | 1 critical, 1 high, 1 medium |

---

### Findings

#### [VALUE-001] HIGH — Value proposition not formalized as falsifiable statement (toolset)
- **Layer:** 1 — Value
- **Location:** README.md (line 9), docs/src/index.md
- **What's wrong:** The README states "turning a 30-minute CI suite into a 30-second feedback loop on most PRs" — this contains outcome, amount (30s vs 30min), and user segment (Julia devs), but it lacks a METRIC, TIMEFRAME, and a formal commitment. It is an effective elevator pitch but not a falsifiable value proposition. No document exists filling all slots of `[TOOL] will enable [USER SEGMENT] to [OUTCOME] by [AMOUNT] within [TIMEFRAME], as measured by [METRIC], compared to [BASELINE]`.
- **Why it matters:** Without a falsifiable VP, the project cannot distinguish "progress" from "activity." The 1358→1546 test-count increase is an output, not an outcome — it proves nothing about value delivery.
- **Recommendation:** Write a falsifiable VP filling all slots. Example: "Testimonial.jl will enable Julia monorepo maintainers to reduce CI test time per PR by 90% (from 30min to 30s median) within 90 days of adoption, as measured by CI pipeline duration for selective runs, compared to running the full suite."

#### [VALUE-002] HIGH — No kill criteria with named owners (toolset)
- **Layer:** 1 — Value
- **Location:** No existing document
- **What's wrong:** No kill criteria document exists. No pre-committed threshold for project failure.
- **Why it matters:** Without kill criteria, the project can drift indefinitely — accumulating features without ever justifying its existence. The beads backlog (nl2b epic, 7 tickets) focuses on architecture quality, not existential value validation.
- **Recommendation:** Draft ≥3 kill criteria with specific metrics, thresholds, dates, and named decision owners. Sign them.

#### [VALUE-003] MEDIUM — No independent evaluation (toolset)
- **Layer:** 1 — Value
- **Location:** Entire project
- **What's wrong:** The building team is the sole measurer. No independent evaluation mechanism exists for the value proposition.
- **Why it matters:** Structural conflict of interest — "we missed the metric but look at this other one" is the most common honesty failure.
- **Recommendation:** Identify an independent evaluator (another team member not in the sprint, or an automated value dashboard) and a minimum cadence.

#### [GOV-001] MEDIUM — AGENTS.md lacks BSD structure (toolset→agent)
- **Layer:** 2 — Governance
- **Location:** AGENTS.md (174 lines)
- **What's wrong:** AGENTS.md contains agent workflow instructions but is not structured as a Behavioral Specification Document — it lacks explicit prohibited behaviors, escalation triggers (beyond "if a tool call fails 2× in a row"), behavioral success metrics, and a scope gate. The .wai/AGENTS.md focuses on wai tool usage, not agent behavior.
- **Why it matters:** Without a BSD, every agent session is governed by accumulated conventions, not an auditable behavioral contract.
- **Recommendation:** Restructure AGENTS.md to include: the falsifiable VP (Goal Sandwich at top/bottom — see PROMPT-002), ≥5 explicit prohibited behaviors (negation form — see PROMPT-004), 7 escalation triggers (see PROMPT-003), behavioral success metrics. This single restructuring unifies GOV-001, PROMPT-002, PROMPT-003, PROMPT-004 into one edit.

#### [GOV-002] MEDIUM — No scope gates at milestones (agent)
- **Layer:** 2 — Governance
- **Location:** beads issue lifecycle
- **What's wrong:** The TDD pipeline does not include behavioral scope gates. A ticket closes when tests pass, not when behavioral alignment is verified.
- **Why it matters:** Enables "scope creep by proxy" — individually reasonable features accumulate without behavioral footprint review.
- **Recommendation:** Add a brief scope check before each `bd close` (did this change expand the agent's behavioral scope?).

#### [PROMPT-001] CRITICAL — No eval suite for agent behavior (agent)
- **Layer:** 3 — Runtime Prompt
- **Location:** AGENTS.md, justfile, workflow
- **What's wrong:** NO eval suite measures agent behavior against an objective. The test suite (`just test`, 1546 tests) measures product correctness, not agent behavior. **Every prompt clause in AGENTS.md (48 actionable clauses counted) lacks a corresponding eval test** — the governing invariant is broken at scale.
- **Why it matters:** Without an agent eval suite, behavioral drift is undetectable during a session. If the model changes, a prompt accumulates, or context overload causes a clause to be ignored, there is zero signal.
- **Recommendation:** Create a minimal eval suite (≥10 cases, ≥30% failure-class) testing: TDD compliance, wai recording, scope respect, escalation triggers. Run as `just agent-check`. Estimate: 1 sprint.

#### [PROMPT-002] HIGH — No Goal Sandwich in system prompt (agent)
- **Layer:** 3 — Runtime Prompt
- **Location:** AGENTS.md
- **What's wrong:** The project's value proposition does not appear verbatim at the TOP and BOTTOM of AGENTS.md. After a long session, the objective is statistically underweighted by the model (U-shaped attention curve).
- **Why it matters:** Without a Goal Sandwich, agent behavior drifts toward locally salient goals rather than the value proposition.
- **Recommendation:** Add the falsifiable VP as PRIMARY OBJECTIVE at both top and bottom of AGENTS.md (identical wording). Estimate: 5 min. (Consolidated into GOV-001 restructuring.)

#### [PROMPT-003] HIGH — Escalation triggers are implicit (agent)
- **Layer:** 3 — Runtime Prompt
- **Location:** AGENTS.md: "If a tool call fails 2× in a row, stop and report"
- **What's wrong:** Only ONE escalation trigger specified. The 7 named triggers from the framework are absent: ambiguity, scope uncertainty, irreversibility, unexpected state, conflicting instructions, high stakes, confidence below threshold.
- **Why it matters:** Without structured escalation, the agent continues through conditions that should trigger human-in-the-loop checks — potentially causing irreversible damage.
- **Recommendation:** Add all 7 escalation triggers with specific decision rules. Estimate: 15 min. (Consolidated into GOV-001 restructuring.)

#### [PROMPT-004] MEDIUM — Scope fence is implicit; Minimal Footprint partial (agent)
- **Layer:** 3 — Runtime Prompt
- **Location:** AGENTS.md, "Context discipline" section
- **What's wrong:** Prohibited behaviors are not explicitly negated (except `git add -A` and `bd close` before push). The AGENTS.md has a resource-constraint minimal footprint in "Context discipline" (summarize output >50 lines, read only relevant sections of files >200 lines) but no **behavioral** Minimal Footprint clause ("don't refactor unrelated code, don't expand scope beyond the ticket").
- **Why it matters:** Implicit prohibitions are unreliable — the model must infer what's not allowed.
- **Recommendation:** Add a PROHIBITED ACTIONS section with ≥5 explicit negations plus a behavioral Minimal Footprint clause. Estimate: 10 min. (Consolidated into GOV-001 restructuring.)

#### [INFRA-001] HIGH — No decay detection dashboard (toolset→agent)
- **Layer:** 4 — Infrastructure
- **Location:** Entire project
- **What's wrong:** No dashboard tiers behavioral health (eval pass rate, scope violations), adoption health, and value health. Beads provides issue analytics but no drift detection.
- **Why it matters:** Without a decay dashboard, drift is only detectable after a critical incident or lagging outcome failure.
- **Recommendation:** Stand up a minimal dashboard extracting `bd list` counts, agent session frequency, eval pass rate, and primary value metric. Estimate: 30 days.

#### [INFRA-002] MEDIUM — No value realization review scheduled (toolset)
- **Layer:** 4 — Infrastructure
- **Location:** Project cadence
- **What's wrong:** No quarterly ceremony to restate VP, review evidence, and decide continue/pivot/kill.
- **Why it matters:** The nl2b epic audits "architecture, performance, and quality-gate risk" — but not "are we building the right thing?"
- **Recommendation:** Schedule within 90 days. Agenda: restate VP → review evidence → gap analysis → continue/pivot/kill.

#### [INTEG-001] CRITICAL — No traceability matrix: decisions → prompts → evals (toolset→agent)
- **Layer:** Integration
- **Location:** All artifacts
- **What's wrong:** The governing invariant states: "Every governance decision must have a corresponding prompt clause, and every prompt clause must have a corresponding eval test." In this project: governance decisions exist (AGENTS.md, wai designs, beads lifecycle), prompt clauses exist (AGENTS.md: 48 actionable clauses identified), but NO eval tests exist for any prompt clause. The loop is entirely open on the verification side.
- **Why it matters:** The agent could follow none of AGENTS.md's instructions and the only detection would be the user noticing.
- **Recommendation:** Create a traceability matrix with columns: Governance Decision → AGENTS.md Clause → Eval Test ID. Start with the 5 most important: TDD pipeline, wai capture, scope boundaries, escalation, confidentiality. Estimate: 30 min.

#### [INTEG-002] HIGH — Shared vocabulary not documented (toolset)
- **Layer:** Integration
- **Location:** AGENTS.md, beads, wai, espectacular
- **What's wrong:** Terms like "epic" (beads), "project" (wai), "change" (openspec), "layer" (architecture) are not mapped to each other or to the agent-value-alignment vocabulary.
- **Why it matters:** Inconsistent vocabulary prevents tracing behavioral observations to governance decisions.
- **Recommendation:** Create a shared vocabulary document mapping concepts across beads/wai/espectacular/AGENTS.md. Estimate: 30 min.

#### [INTEG-003] MEDIUM — Value proposition not propagated verbatim (toolset→agent)
- **Layer:** Integration
- **Location:** README.md, AGENTS.md, docs/src/
- **What's wrong:** The VP appears in README.md and docs but NOT verbatim in AGENTS.md (the agent's runtime prompt). No trigger exists to keep all three in sync when the VP changes.
- **Why it matters:** Without the VP in its runtime context, the agent optimizes for locally salient goals (close the next ticket).
- **Recommendation:** Add VP verbatim to top and bottom of AGENTS.md. Add to `just check` gate output. Ensure all three locations stay in sync. (Consolidated into GOV-001 restructuring.)

---

### Limitations

1. **Self-audit bias.** This audit was performed by the same agent being audited (pi self-auditing its behavior on Testimonial.jl). This introduces a structural blind spot: the agent cannot identify systematic behavioral drift it shares with the audit framework. Findings that require external perspective (e.g., "does the agent consistently over-emphasize closure rate over value?") are unaddressable in a self-audit. **Recommendation:** cross-validate findings with a human reviewer or a different agent model before acting on the recommended priority order.

2. **Single-agent scope.** The analysis treats pi as the sole agent, but beads (issue automation), pretender (commit hooks), and CI (GitHub Actions) are automated systems with their own behavioral properties. Multi-agent drift types (orchestrator drift, worker drift, coordination drift, emergent drift per Layer-2 §Multi-agent systems) are not evaluated. **Recommendation:** extend to a multi-agent audit if beads/pretender/CI behavior changes significantly.

3. **Point-in-time snapshot.** This audit reflects the state of the project at 2026-08-01. AGENTS.md changes, model updates, beads workflow evolution, and prompt accumulation can each cause findings to become stale. **Recommendation:** re-run this audit quarterly, or after any of: a model update, a major AGENTS.md restructuring, a prompt-size change >20%, or a beads version bump.

---

### Invariant Check

| Check | Count | Details |
|---|---|---|
| Governance decisions with no prompt clause | ~30 | All decisions in AGENTS.md have prompt clauses (they ARE prompt clauses) — no enforcement gap found |
| Prompt clauses with no eval test | **48** | Every actionable instruction in AGENTS.md (counted: conditionals, prohibitions, procedures, and context-discipline rules) has ZERO corresponding eval tests for agent behavior |
| Eval results not reviewed in governance | N/A | No agent behavior eval suite exists — cannot review what isn't measured |

**Status:** Critical. The entire prompt layer (AGENTS.md, 48 clauses) is unverified. No feedback loop exists.

---

### Value Proposition (as currently stated)

> "Testimonial is a Julia-native test impact analysis engine. Given code changes (from a git diff), it selects the minimal set of @testitems required to validate those changes — turning a 30-minute CI suite into a 30-second feedback loop on most PRs."

**Falsifiable?** Partially — it has outcome (30s vs 30min), user segment (Julia monorepo devs), and context (most PRs). Lacks: METRIC (CI pipeline duration? developer wait time?), TIMEFRAME (90 days? 6 months?), BASELINE (which repos? which CI configs?). "Most PRs" is an unfalsifiable hedge — what threshold is "most"?

**Propagated verbatim across prompt + BSD + review agenda?** No. Appears in README.md and docs, not in AGENTS.md.

---

### Kill Criteria Status

**NOT DEFINED.** No kill criteria document exists.

---

### Recommended Actions (priority order)

1. **[INTEG-001]** Create traceability matrix for the 5 most important decisions — Owner: pi maintainer — Layer: Integration — Estimate: 30 min
2. **[PROMPT-001]** Create agent behavior eval suite (≥10 cases, ≥30% failure-class) as `just agent-check` — Owner: pi maintainer — Layer: 3 — Estimate: 1 sprint
3. **[GOV-001 / PROMPT-002/003/004 / INTEG-003]** Restructure AGENTS.md into a BSD with Goal Sandwich, 7 escalation triggers, PROHIBITED ACTIONS (≥5), behavioral Minimal Footprint, and verbatim VP — Owner: pi maintainer — Layer: 2+3+Integration — Estimate: 2h
4. **[VALUE-001]** Write formal falsifiable VP with all slots filled — Owner: project owner — Layer: 1 — Estimate: 30 min
5. **[VALUE-002]** Write and sign kill criteria document (≥3 criteria) — Owner: project owner — Layer: 1 — Estimate: 1h
6. **[INTEG-002]** Create shared vocabulary document mapping beads/wai/espectacular/AGENTS.md — Owner: pi maintainer — Layer: Integration — Estimate: 30 min
7. **[INFRA-001]** Stand up decay detection dashboard (3 tiers: behavioral, adoption, value) — Owner: pi maintainer — Layer: 4 — Estimate: 30 days
8. **[INFRA-002]** Schedule first value realization review within 90 days — Owner: project owner — Layer: 4 — Estimate: 90 days out

### Next Review

**Value Realization Review scheduled:** NOT SCHEDULED — schedule within 90 days
**Recurrence:** Re-run this audit quarterly, or after any model/prompt/governance change. See Limitations §3.
**Decay dashboard live:** No