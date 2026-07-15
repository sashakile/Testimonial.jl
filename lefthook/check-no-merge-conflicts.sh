#!/usr/bin/env bash
# Check for unresolved merge conflict markers
set -euo pipefail

if [ $# -eq 0 ]; then
  exit 0
fi

matches=$(grep -rn "^<<<<<<< \|^=======$|^>>>>>>> " "$@" 2>/dev/null || true)
if [ -n "$matches" ]; then
  echo "Error: Merge conflict markers found:"
  echo "$matches"
  exit 1
fi