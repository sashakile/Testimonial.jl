# Testimonial.jl — Value Proposition & Kill Criteria

## Falsifiable Value Proposition

**Canonical statement (verbatim, must appear in AGENTS.md, BSD, and review agendas):**

> Testimonial is a Julia-native test impact analysis engine. Given code changes (from a git diff), it selects the minimal set of @testitems required to validate those changes — turning a 30-minute CI suite into a 30-second feedback loop on most PRs.

**Falsifiable form (fills all slots):**

> Testimonial.jl will enable **Julia monorepo maintainers** (USER SEGMENT) to **reduce CI test time per PR** (OUTCOME VERB + OBJECT) by **90%** (AMOUNT) — from **30 minutes median full-suite runtime down to 30 seconds median selective-run runtime** — within **90 days of project adoption** (TIMEFRAME), as measured by **CI pipeline duration for selective runs across ≥5 production Julia monorepos** (METRIC), **compared to running the full suite on every PR** (BASELINE).

### Falsifiability test

This VP is falsifiable because:
1. A specific, measurable METRIC exists (CI pipeline duration)
2. A BASELINE is stated (full-suite runtime vs selective-run runtime)
3. A TIMEFRAME is stated (90 days post-adoption)
4. A clear FAILURE condition exists: if after 90 days the median improvement is <90% on ≥5 repos, the VP is false

### What we are NOT promising

- 100% precision (some PRs require full runs — "most PRs," not "all PRs")
- Zero setup cost (recording coverage requires an initial `record_all()` run)
- Cross-language support (Julia-only)
- Support for non-@testitem test frameworks

---

## Kill Criteria

Each criterion is a pre-committed stopping condition. If ANY criterion is
triggered, the project owner must call a Value Realization Review (within
14 days) with a continue/pivot/kill decision.

| # | Metric | Threshold | Timeframe | Consequences if triggered | Decision owner |
|---|--------|-----------|-----------|--------------------------|----------------|
| 1 | **Selection precision** (of selected tests, how many would have failed anyway?) | <80% precision over any trailing 30-day window | Measured from first production deployment | Revert to full-suite-only mode; investigate root cause before re-enabling selective runs | Project owner |
| 2 | **Selection recall** (of tests that would fail, how many were selected?) | <95% recall over any trailing 30-day window | Measured from first production deployment | Flag as HIGH priority incident; file incident report; if persists 2 cycles, consider architecture redesign | Project owner |
| 3 | **Adoption rate** | <2 actively using repos after 6 months from v1.0 release | 6 months post-v1.0 | Sunset experiment; archive repo; document lessons learned | Project owner |
| 4 | **CI time savings** | <50% median reduction in CI test time per PR | 6 months post-v1.0 | Pivot: reduce feature scope, focus on the most impactful 20% of the use case | Project owner |

### Signatures

These kill criteria are pre-committed and signed before further development
on the selective-run feature.

- **Owner:** [to be signed] — Date: [to be filled]
- **Reviewer:** [to be signed] — Date: [to be filled]

*Kill criteria are living documents — they should be reviewed quarterly at
each Value Realization Review and updated via BADR if needed, but the default
is to honor them as written.*

---

## Measurement Plan

| Signal type | Indicator | Leading/Lagging | Source |
|---|---|---|---|
| Output | Number of @testitem blocks discovered | Leading | `discover` command output |
| Output | Coverage index size and freshness | Leading | `index_info()` |
| Outcome | Selective-run CI duration vs full-suite baseline | Leading | CI pipeline logs |
| Outcome | Selection precision (false positives) | Leading | Reconciliation results (`reconcile()`) |
| Outcome | Selection recall (missed failures) | Lagging | Incident detection (`missed_selection_incidents`) |
| Impact | Developer time saved per week | Lagging | User survey / CI wait-time reduction |
| Impact | Adoption rate (repos using Testimonial) | Lagging | Repository count |

**Countermeasure against Goodhart's Law:** Precision and recall are measured
in healthy tension — optimizing for one at the expense of the other is
detectable. Multiple metrics are tracked as trends, not point values.