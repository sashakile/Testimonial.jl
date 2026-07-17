set shell := ["bash", "-euo", "pipefail", "-c"]

# ── Default ────────────────────────────────────
default:
    @just --list

# ── Julia package commands ─────────────────────
install:
    julia --project -e 'import Pkg; Pkg.instantiate()'

test:
    julia --project test/runtests.jl

# Run tests excluding slow subprocess tests (fast pre-push check)
test-quick:
    julia --project test/runtests_quick.jl

coverage:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; Testimonial.record_all()'

record:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; Testimonial.record_all(incremental=true)'

run:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; Testimonial.smart_run()'

shadow-run:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; Testimonial.smart_run(shadow=true)'

reconcile:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; Testimonial.reconcile()'

seed-fault-test:
    julia --project=scripts/TestimonialRunner scripts/seeded_fault_test.jl

explain *args:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; for r in Testimonial.explain(ARGS[1], ARGS[2]); println(r); end' {{args}}

history:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; Testimonial.history()'

info:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; println(Testimonial.index_info())'

docs:
    julia --project=docs/ -e 'using LiveServer; servedocs()'

# ── Spec management ────────────────────────────
specs:
    openspec validate --specs

specs-list:
    openspec spec list --long

changes:
    openspec list

# ── Code quality ───────────────────────────────
# Run pretender code quality checks
lint:
    pretender check

# Generate pretender report
lint-report:
    pretender report

# Show code complexity hotspots
complexity:
    pretender complexity

# Show code duplication
duplication:
    pretender duplication

# Mutation testing
mutation:
    pretender mutation

# ── Spec-level checks ──────────────────────────
# Run espectacular spec-level validation
ah-check:
    espectacular check

# Archive a completed openspec change (usage: just archive-change <id>)
archive-change id:
    openspec archive {{id}} --yes

# ── Test selection ────────────────────────────
# Initialize or update testaruda dependency graph
testaruda-discover:
    testaruda discover

# Select affected tests from a code change
testaruda-select:
    testaruda select

# Show testaruda dependency graph
testaruda-graph:
    testaruda graph

# Ingest test results into testaruda
testaruda-ingest:
    testaruda ingest

# ── Beads / issue tracking ────────────────────
bd-ready:
    bd ready

bd-list:
    bd list --status=open

bd-show id:
    bd show {{id}}

bd-create title description:
    bd create --title="{{title}}" --description="{{description}}"

bd-close id:
    bd close {{id}}

# Export issues to JSONL for git-based portability
bd-export:
    bd export -o .beads/issues.jsonl

bd-sync:
    bd dolt push
    bd export -o .beads/issues.jsonl

# ── Session management ────────────────────────
session-start:
    wai sync
    wai status
    bd ready
    openspec list

session-end:
    wai close

handoff:
    wai handoff create testimonial-mvp

# ── Health checks ──────────────────────────────
doctor:
    wai doctor
    pretender doctor
    espectacular doctor
    lefthook check-install

# Full quality gate — run before pushing
check: test specs lint doctor