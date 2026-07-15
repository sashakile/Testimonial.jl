#!/usr/bin/env bash
# Check Julia syntax for staged files
set -euo pipefail

if [ $# -eq 0 ]; then
  exit 0
fi

for file in "$@"; do
  if [[ "$file" == *.jl ]]; then
    julia -e "
      try
        Meta.parseall(read(\"$file\", String))
      catch e
        println(\"syntax error: $file: \$e\")
        exit(1)
      end
    " 2>/dev/null
  fi
done