set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

install:
    julia --project -e 'import Pkg; Pkg.instantiate()'

test:
    julia --project -e 'import Pkg; Pkg.test()'

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

explain:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; for r in Testimonial.explain(ARGS[1], ARGS[2]); println(r); end'

history:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; Testimonial.history()'

info:
    julia --project=scripts/TestimonialRunner -e 'using Testimonial; println(Testimonial.index_info())'

docs:
    julia --project=docs/ -e 'using LiveServer; servedocs()'

specs:
    openspec validate --specs

doctor:
    wai doctor

status:
    wai status

check: test specs doctor
