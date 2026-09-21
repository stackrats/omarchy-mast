#!/bin/bash

# Lints the QML with Qt 6's qmllint when it is installed. The shell's own
# modules (qs.Commons, qs.Ui) resolve only with an Omarchy checkout to import
# from, so point OMARCHY_PATH at one for the full check; without it, or
# without qmllint, the test skips rather than pretending.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if ! command -v qmllint >/dev/null 2>&1 || ! qmllint --version >/dev/null 2>&1; then
  pass "qmllint not installed; skipping QML lint"
  exit 0
fi

args=()
if [[ -n ${OMARCHY_PATH:-} && -d $OMARCHY_PATH/shell ]]; then
  args+=(-I "$OMARCHY_PATH/shell")
fi

for file in "$ROOT"/*.qml; do
  if output=$(qmllint "${args[@]}" "$file" 2>&1); then
    pass "qmllint accepts $(basename "$file")"
  else
    fail "qmllint accepts $(basename "$file")" "$output"
  fi
done
