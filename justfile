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
