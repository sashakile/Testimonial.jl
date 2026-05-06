set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

install:
    julia --project -e 'import Pkg; Pkg.instantiate()'

test:
    julia --project -e 'import Pkg; Pkg.test()'

coverage:
    julia --project -e 'import Pkg; Pkg.test()' -- --coverage

docs:
    julia --project=docs/ -e 'using LiveServer; servedocs()'

specs:
    openspec validate --specs

doctor:
    wai doctor

status:
    wai status

check: test specs doctor
