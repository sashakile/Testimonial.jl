# Testimonial.jl — Shared Vocabulary

Maps each concept across the four governance frameworks to ensure
behavioral observations can be traced to governance decisions.

| Concept | AGENTS.md (agent prompt) | beads (issues) | wai (decisions) | espectacular (contracts) | Agent-Value-Alignment (this audit) |
|---|---|---|---|---|---|
| Agent / Assistant | "agent" / "you" | N/A | N/A | N/A | **Target** — runtime agent being governed |
| What the agent is trying to do | **PRIMARY OBJECTIVE** (Goal Sandwich) | Issue description / AC | Project outcome | Spec scope | **Value proposition** |
| Unit of work | Ticket / task | **Issue** (type: bug/feature/task/epic) | **Work item** / decision | **Change proposal** | **Task** / **Governance decision** |
| Work lifecycle | TDD pipeline: RED→GREEN→REFACTOR | Status: open→in_progress→closed | Phase: research→decide→implement→review | Stage: draft→validate→deploy→archive | **AUDIT→ESTABLISH→REVIEW** |
| What the agent must not do | **PROHIBITED ACTIONS** | Issue labels (e.g., `blocked`) | Scope boundary in design doc | Contract's invariant section | **Prohibited behavior** |
| When to stop and ask | **Escalation Triggers** (7 named) | N/A | — decisions | — validation failures | **Human-in-the-loop boundary** |
| How we know it worked | Passing test suite | Acceptance criteria closed | Decision closed with rationale | `ah check` passes | **Eval test** |
| What the agent should build smallest | **Behavioral Principles → Proportionality** | — scope | — design constraints | — size estimates | **Minimal Footprint** |
| Value delivery | **PRIMARY OBJECTIVE** (verbatim VP) | Issue impacts | Outcome tracking | Spec's "success criteria" | **Value proposition / outcome** |
| Misalignment / drift | Escalation triggers / context warning | — regression labels | — drift detected | — structural issues | **Behavioral drift** |
| Audit trail | Session log / whisper notes | `interactions.jsonl` | `designs/`, `research/` | `openspec/changes/` archive | **Evidence / traceability** |
| Decision record | N/A | Issue status history | **BADR** (Behavioral ADR) | Proposal + design + tasks | **Governance decision** |
| Behavioral boundary | **PROHIBITED ACTIONS** + Escalation Triggers | Metadata `scope` | Scope gates | Contract invariants | **Scope** |
| Quality gate | `ah check` before commit | `bd close` + push | `wai close` | `ah check --run-tests` | **Eval pass** |

## Cross-reference by framework

When reading artifacts from one framework, use the table above to find the
corresponding concept in the others. For example:

- A beads **issue** with `metadata.files` is the implementation side of a
  **governance decision** that should appear in a **wai design** and be
  enforced by an **AGENTS.md PROHIBITED ACTIONS** clause.
- An **espectacular** `ah check` failure is the contract-level signal of
  **behavioral drift** — the same drift the **AGENTS.md escalation triggers**
  aim to prevent at runtime.
- A **wai research note** is the evidence for a **governance decision** that
  should propagate to a **prompt clause** in AGENTS.md and a **contract test**
  in espectacular.