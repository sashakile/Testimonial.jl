# Spec Evaluation Report: sashakile/Testimonial.jl (OpenSpec proposals)

**Date:** 2026-07-15
**Reviewer:** pi agent (specification-evaluation-diagnostician protocol)
**Source:** https://github.com/sashakile/Testimonial.jl
**Scope:** All 6 OpenSpec change proposals under `openspec/changes/` — nothing
has been archived to `openspec/specs/` yet (`openspec list --specs` → "No
specs found"; all changes at 0/N tasks), so this is a pre-implementation
review.

**Method:** Cloned the repo, read every `proposal.md` / `design.md` /
`tasks.md` / `specs/*/spec.md` in full, ran the actual `openspec` CLI
(`validate --strict`, `list`, `show --json --deltas-only`) rather than
relying on manual reading alone, and cross-checked claims in
`openspec/project.md` against the delta files on disk. No implementation
code exists yet (`src/` is not present) — this review covers specification
artifacts only.

**Caveat:** This is an AI-assisted diagnostic pass. CRITICAL/HIGH findings
were cross-checked against `openspec` CLI output and `rg` searches against
the source repo where possible (noted inline), but treat this as structured
triage, not ground truth — the author/maintainer should re-verify before
acting, especially on the naming-convention judgment call in COHR-3.1.

## Summary

```
Requirements Evaluated: 53 (CI-001..005=5, REC-001..011=11, SEL-001..007=7,
                         COMP-001..006=6, CONF-001..004=4, PROV-001..004=4,
                         FEED-001..005=5, SAFE-001..011=11)
Governance Documents Referenced: openspec/project.md, openspec/AGENTS.md

Dimension Scores:
  Completeness: WEAK
  Correctness:  WEAK
  Coherence:    DEFICIENT

Overall Verdict: NEEDS_REWORK
```

Two systemic, tool-confirmed structural failures run through **five of the
six** proposals identically (naming mismatch + Impact/delta mismatch) — see
Verdict Rationale below for the full explanation.

## Recommended Actions (in dependency order)

1. Rename each `specs/<change-id>/` delta folder to the `project.md`
   capability name (COHR-3.1), and split each change's single delta file
   into the correct per-capability delta files with real MODIFIED
   requirements (COMP-3.2). Do these two together — they're the same fix.
2. Add a scenario to `[REC-011]` so `openspec validate
   implement-coverage-layer --strict` passes (COMP-1.1).
3. Resolve the add-runtime-feedback ↔ add-safety-invariants circular
   dependency (COHR-3.3) — either resequence or move the FEED-002 flaky
   scenario into safety-invariants.
4. Fix the `layer_coverage` formula and the 0.5/0.7 threshold conflict in
   add-confidence-scoring (CORR-2.1, CORR-2.2).
5. Define `layer_data`/`manual_edges` in the data model (COMP-1.2); add the
   missing `add-component-boundary` dependency to add-confidence-scoring
   (COMP-1.3).
6. Resolve or properly cite "testaruda" (COHR-3.4); relocate the misplaced
   git-repository scenario out of COMP-001 (COHR-3.5).

## Findings

### [COHR-3.1] CRITICAL — Capability naming mismatch across 5/6 changes

**Dimension:** Coherence (Architectural Drift)
**Location:** `openspec/project.md` (Capability Specs table) vs. `openspec/changes/*/specs/`

`openspec/project.md`'s Capability Specs table declares the capability IDs
as `component-architecture`, `confidence-scoring`, `provenance`,
`runtime-feedback`, `safety-invariants`. But every one of those five changes
stores its delta under a spec folder named after the **change-id**, not the
capability:

- `specs/add-component-boundary/` (should be `component-architecture`)
- `specs/add-confidence-scoring/` (should be `confidence-scoring`)
- `specs/add-provenance-explainability/` (should be `provenance`)
- `specs/add-runtime-feedback/` (should be `runtime-feedback`)
- `specs/add-safety-invariants/` (should be `safety-invariants`)

Confirmed via `openspec show <change> --json --deltas-only`: the delta's
`"spec"` field is literally `"add-component-boundary"`, not
`"component-architecture"`. Only `implement-coverage-layer` gets this right
(`coverage-index`, `recording`, `smart-selection` match project.md exactly).

**Impact:** `openspec validate --strict` passes today (it doesn't
cross-check project.md), but archiving any of these five changes will
create five wrongly-named one-off capabilities instead of merging into the
capability taxonomy project.md documents. A future change that says
"MODIFIED confidence-scoring" will silently create a *sixth*, duplicate
capability. Tie-breaker: `openspec/AGENTS.md`'s own archiving model says
"Move `changes/[name]/` → archive; Update `specs/` if capabilities
changed" — this only makes sense if deltas already target the real
capability name, which is the reading this finding assumes.

**Remediation:** Rename each `specs/<change-id>/` delta folder to the
project.md capability name before these are approved.

### [COMP-3.2] CRITICAL — Declared Impact never materializes as deltas (all 5 non-Phase-1 changes)

**Dimension:** Completeness (Unmapped Requirement) / Coherence (Scope Contradiction)
**Location:** `openspec/changes/{add-component-boundary,add-confidence-scoring,add-provenance-explainability,add-runtime-feedback,add-safety-invariants}/proposal.md` (`## Impact` sections) vs. their `specs/` directories

Every one of the 5 later proposals' `## Impact` section claims to MODIFY
existing capabilities. Example, `add-safety-invariants`:

> Affected capabilities: `smart-selection` (MODIFIED smart_run
> orchestration), `ci-integration` (ADDED incident detection...)

But the change's `specs/` directory contains exactly **one** file, targeting
only the new capability (see COHR-3.1) — there is no
`specs/smart-selection/spec.md` delta, no `specs/ci-integration/spec.md`
delta, in any of the 5 changes. Same pattern in `add-component-boundary`
(claims `coverage-index`/`recording`/`smart-selection`/`ci-integration`
MODIFIED — zero deltas for any), `add-confidence-scoring`,
`add-provenance-explainability`, `add-runtime-feedback`.

**Impact:** The actual behavioral changes to `smart_run`, `query`,
`CoverageIndex`, etc. narrated in prose (e.g. "Modify `query` to accept
component scope", "Add `ingest` call to `smart_run` after `runtests`
exits") are never captured as normative ADDED/MODIFIED requirements against
the capabilities they actually touch. An implementer following only
`specs/` would miss all of this.

**Remediation:** For each change, add delta files under
`specs/smart-selection/spec.md`, `specs/coverage-index/spec.md`, etc. with
`## MODIFIED Requirements` entries (full requirement text, per
`openspec/AGENTS.md` authoring rules) instead of dumping everything into one
orphan capability.

### [CORR-2.1] CRITICAL — `layer_coverage` confidence formula contradicts its own worked example

**Dimension:** Correctness (Incorrect Technical Claim / Internal Contradiction)
**Location:** `add-confidence-scoring/design.md`, Decision 1

Formula given: `layer_coverage = 1 / (num_layers_available + 1)`, annotated
"(more layers → higher ceiling; 1 layer = 0.5, 3 = 0.75)".

Plugging in the stated formula: 1 layer → 1/2 = 0.5 ✓, but 3 layers → 1/4 =
0.25, **not** 0.75 — and the formula is monotonically *decreasing* in
`num_layers`, directly contradicting "more layers → higher ceiling."
`tasks.md` 1.4 independently states "1 layer = 0.5, 2 = 0.67, 3 = 0.75",
which matches `num_layers / (num_layers + 1)` — the numerator and
denominator appear swapped in `design.md`.

**Impact:** Implemented as written, more analysis layers would *lower*
confidence — the opposite of intent. A silent correctness bug baked into the
spec.

**Remediation:** Fix `design.md` to
`layer_coverage = num_layers_available / (num_layers_available + 1)`.

### [CORR-2.2] CRITICAL — Confidence threshold default conflict (0.7 vs 0.5)

**Dimension:** Correctness / Coherence (Internal Contradiction)
**Location:** `add-confidence-scoring`

`design.md` Goals ("default 0.7") and Decision 2 ("default threshold 0.7")
both say 0.7. `design.md` Risks table says "start with conservative 0.5
default." The normative spec, CONF-003, says "The default threshold SHALL
be 0.5." Two different default values are asserted as fact in the same
proposal, and the normative requirement disagrees with the design rationale
meant to justify it.

**Impact:** Ambiguous for implementers and for anyone tuning
`confidence_threshold` in `Testimonial.toml` — which default is "the spec"?

**Remediation:** Pick one value; correct `design.md` to match `spec.md` (or
vice versa) and remove the stale figure.

### [COHR-3.3] CRITICAL — Circular requirement dependency: add-runtime-feedback ↔ add-safety-invariants

**Dimension:** Coherence (Architectural Drift / undeclared circular dependency)
**Location:** `add-runtime-feedback/specs/.../spec.md` (FEED-002) vs. `add-safety-invariants/specs/.../spec.md` (SAFE-007) and `add-runtime-feedback/proposal.md` (Dependencies)

`add-safety-invariants` correctly declares (in `proposal.md`) that it
depends on `add-runtime-feedback` ("for missed-selection recording and
ingest"). But `add-runtime-feedback`'s own normative requirement FEED-002
("Flaky test edge exclusion" scenario) reads:

> GIVEN a test marked flaky (see SAFE-007) ... runtime edges from that test
> SHALL NOT be ingested

SAFE-007 (flaky detection/quarantine) is defined only in
`add-safety-invariants`. `add-runtime-feedback`'s own `Dependencies` section
lists only `implement-coverage-layer` — never `add-safety-invariants`.
`add-safety-invariants/tasks.md` 5.3 confirms the mutual reference ("Add
flaky test edge exclusion ... (FEED-002 interaction)").

**Impact:** The stated implementation order (runtime-feedback before
safety-invariants, since safety-invariants depends on it) makes FEED-002's
flaky-exclusion scenario impossible to implement when runtime-feedback is
built — the concept it requires doesn't exist yet. A genuine circular
dependency hidden by an undeclared one-way arrow.

**Remediation:** Either (a) declare `add-safety-invariants` as a dependency
of `add-runtime-feedback` and resequence, or (b) move the SAFE-007-dependent
scenario out of FEED-002 into `add-safety-invariants` as a MODIFIED
requirement instead (where the dependency is already correctly declared).

### [COMP-1.1] CRITICAL (tool-confirmed) — REC-011 requirement has no scenario

**Dimension:** Completeness (Orphaned Requirement)
**Location:** `implement-coverage-layer/specs/recording/spec.md`, `[REC-011] Runner decoupling`

`openspec validate implement-coverage-layer --strict` fails today:

```
✗ [ERROR] recording/spec.md: ADDED "[REC-011] Runner decoupling" must
  include at least one scenario
```

Verified directly against the CLI, not inferred.

**Impact:** Blocks `tasks.md` item 10.5 ("Verify `openspec validate
implement-coverage-layer --strict` passes") — Phase 1 cannot be marked done
per its own acceptance criterion.

**Remediation:** Add a `#### Scenario:` block to REC-011, e.g. testing that
a `MockRunner` produces the expected command/args without spawning a
process (this is exactly what REC-002/5.10's task already describes — it
just needs a scenario in the spec).

### [COMP-1.2] HIGH — `layer_data` and "manual edges" referenced but never added to the data model

**Dimension:** Completeness (Unmapped Requirement)
**Location:** `implement-coverage-layer/design.md` (Extensible Query Pipeline decision) and `implement-coverage-layer/specs/coverage-index/spec.md` (CI-001, CI-004); `add-safety-invariants/specs/.../spec.md` (SAFE-005)

`implement-coverage-layer/design.md`'s "Extensible Query Pipeline" decision
introduces `layer_data::Dict{Symbol, Any}` as the mechanism for
layer-specific data, and CI-004 (`CoverageGap`) references it ("no coverage
entry in `line_to_tests` or any other analysis layer registered in
`layer_data`"). But CI-001's actual field list for `CoverageIndex` has no
`layer_data` field — only `inference_edges`/`static_edges` (reserved,
concrete dicts). Separately, SAFE-005 says a confirmed incident is
"promoted to a permanent `manual` edge," but no requirement in any of the 6
changes adds a `manual_edges` (or similarly named) field to `CoverageIndex`.

**Impact:** Two load-bearing concepts (generic layer storage, manual edges)
are used normatively in scenarios but have no field definition anywhere —
an implementer has to invent the storage.

**Remediation:** Add a MODIFIED CI-001 requirement (in whichever change
introduces it first) defining `layer_data` or `manual_edges` explicitly, or
drop the `layer_data` reference from CI-004 and use `inference_edges`/
`static_edges` directly for consistency.

### [COMP-1.3] MEDIUM — Undeclared dependency: add-confidence-scoring → add-component-boundary

**Dimension:** Completeness (Implicit Dependency)
**Location:** `add-confidence-scoring/tasks.md` (2.1) vs. `add-confidence-scoring/proposal.md` (Dependencies)

`add-confidence-scoring/tasks.md` 2.1 says per-component confidence
aggregation "(requires `add-component-boundary`)" — but
`add-confidence-scoring/proposal.md`'s `Dependencies` line lists only
`implement-coverage-layer`, `add-runtime-feedback`, `add-safety-invariants`.
`add-component-boundary` is missing despite being required by a task.

**Impact:** The dependency graph in project docs undercounts the real build
order; someone sequencing work off `proposal.md` alone will hit a missing
prerequisite.

**Remediation:** Add `add-component-boundary` to the Dependencies line.

### [COHR-3.4] MEDIUM — Unverifiable external citations ("testaruda")

**Dimension:** Coherence (Disconnected Rationale) / Correctness (Stale/Unverifiable Reference)
**Location:** 7 files across `openspec/changes/` (see below)

10 references across 7 files cite "testaruda"
and specific rule IDs (`TIA-COMP-003`, `TIA-COMP-012`, `TIA-REL-001`,
`TIA-CONF-002`, `TIA-SAFE-002`, `TIA-PROV-001`, `TIA-ENG-009`,
`TIA-ARCH-003`, `TIA-SEL-004`) as design precedent, e.g. "This matches
testaruda's TIA-ENG-009," "matching testaruda's TIA-SAFE-002 approach."
Verified via `rg -ni testaruda openspec/changes -c`: 5 `design.md` files
(add-runtime-feedback ×1, add-confidence-scoring ×3, add-component-boundary
×1, add-safety-invariants ×1, add-provenance-explainability ×2), plus
`add-component-boundary/proposal.md` ×1, plus
`add-confidence-scoring/specs/.../spec.md` ×1 — 7 files, 10 occurrences
total. "testaruda" is not defined anywhere in the repo — not in
`project.md`'s References section, not in the README, no link, no glossary
entry.

**Impact:** These citations justify non-obvious design decisions (why
reason chains instead of full provenance polynomials, why confidence isn't
path-based, why manual edges need multi-change confirmation) but cannot be
checked by a reviewer. If "testaruda" doesn't exist or was misremembered,
the rationale evaporates; if it does exist, it should be a real,
dereferenceable citation.

**Remediation:** Either add testaruda to `project.md`'s References with a
link, or rewrite the rationale to stand on its own without appeal to an
unverifiable external authority.

### [COHR-3.5] MEDIUM — Scenario misplaced under the wrong requirement

**Dimension:** Coherence (Disconnected Rationale) / ISO 29148 Singular
**Location:** `add-component-boundary` spec.md, `[COMP-001] Component-scoped index`

COMP-001 is about per-component index storage layout. Its third scenario,
"No git repository," is about git-absence fallback behavior — unrelated to
component storage, and arguably belongs under SAFE-003/SAFE-004
(environment fallback) in `add-safety-invariants`, or as its own
requirement.

**Impact:** Minor on its own, but it's a symptom of the same
"one-giant-capability-file" problem as COMP-3.2 — requirements are being
used as a dumping ground rather than kept singular.

**Remediation:** Move the scenario to a dedicated requirement (or to
`safety-invariants` once COMP-3.2 is fixed).

### [ISO-4.1] MEDIUM — SAFE-001 is not independently verifiable

**Dimension:** ISO 29148 Quality (Verifiable)
**Location:** `add-safety-invariants/specs/.../spec.md` (SAFE-001)

SAFE-001 ("a test that could be affected by a code change MUST be
selected... an omission SHALL be treated as a bug") is, on its own, not
objectively testable — "could be affected" requires ground truth about
semantic dependency that no automated check can produce in general.

This is properly mitigated elsewhere (SAFE-010 seeded-fault test, SAFE-009
reconciliation act as operational proxies), so it's not a standalone defect
— but the spec should frame SAFE-001 explicitly as a design invariant
verified indirectly by SAFE-009/SAFE-010, rather than phrasing it with
SHALL/scenario as if it were directly checkable.

## Confirmed Strengths

- **Phase 1 (`implement-coverage-layer`)** is by far the strongest artifact:
  correct capability naming matching `project.md`, a thorough data model
  (CI-001–CI-005), a well-reasoned `design.md` with explicit
  alternatives-considered sections, and concrete failure-mode scenarios
  (subprocess timeout/retry math checks out, corrupted-index handling,
  atomic writes).
- The **safety-invariants** proposal is conceptually the most mature piece
  of design thinking in the set — the shadow-mode → evaluation-window →
  enforcing promotion protocol with a seeded-fault recall gate is a
  genuinely good verification strategy for a tool whose failure mode
  (missed test selection) is silent and dangerous.
- Consistent, disciplined use of `SHALL` / `GIVEN-WHEN-THEN` scenario format
  throughout — format-level `openspec validate` passes cleanly on 5 of 6
  changes.
- Design docs consistently include a Risks/Trade-offs table and Open
  Questions section — good practice, followed uniformly across all 6
  changes.

## Needs Human Judgment

- Whether "testaruda" is a real prior-art system the author has access to
  (in which case it just needs a proper citation) or a
  misremembered/hallucinated reference — this can't be resolved from the
  repo alone.
- Whether the intended workflow really is "one giant capability per change"
  (in which case `project.md`'s capability table is the thing that's wrong,
  not the specs) — but that reading contradicts `openspec/AGENTS.md`'s own
  archiving model ("Move `changes/[name]/` → archive; Update `specs/` if
  capabilities changed" implies deltas target the real capability, not the
  change-id).
- Confidence-threshold default (0.5 vs 0.7) is a product/tuning decision as
  much as a spec bug — needs the author to pick one intentionally, not just
  fix the arithmetic.

## Verdict Rationale

Two independent, tool-confirmed structural failures — the capability-naming
mismatch (COHR-3.1) and the Impact-section/delta-content mismatch
(COMP-3.2) — run through five of the six proposals identically, which is
what pushes Coherence to DEFICIENT rather than WEAK: this isn't an isolated
typo, it's a systemic authoring pattern that will corrupt the
`openspec/specs/` tree the moment any of these changes is archived. Layered
on top are two independently verifiable math/logic errors in the
confidence-scoring design (inverted formula, conflicting defaults) and a
real circular dependency between `runtime-feedback` and `safety-invariants`.
None of this is caught by `openspec validate --strict`, because that tool
checks delta syntax, not cross-references to `project.md` or to the prose
in `Impact` sections — exactly the gap this kind of review is for. Fixing
COHR-3.1/COMP-3.2 (mechanically: move deltas to the right capability folders
and actually write the MODIFIED requirements the prose promises) would very
likely move Coherence and Completeness to WEAK/ADEQUATE; the
confidence-formula bugs and the circular dependency are smaller, targeted
fixes. None of the five later proposals should be approved for
implementation as currently structured.

