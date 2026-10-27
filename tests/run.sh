#!/usr/bin/env bash
# Run each tests/*_spec.lua (or the specs named) in its own headless Neovim.
# Non-zero exit if any fails.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ $# -gt 0 ]; then specs=("$@"); else specs=("$here"/tests/*_spec.lua); fi
status=0
for spec in "${specs[@]}"; do
  [ -f "$spec" ] || spec="$here/tests/$spec"
  echo "== $(basename "$spec")"
  if ! nvim --headless --clean -u "$here/tests/minimal_init.lua" -l "$spec"; then
    status=1
  fi
done
exit $status
