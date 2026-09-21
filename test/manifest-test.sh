#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

bash "$ROOT/scripts/validate.sh" "$ROOT" >/dev/null || fail "manifest passes the shell's validation rules"
pass "manifest passes the shell's validation rules"

id=$(jq -r '.id' "$ROOT/manifest.json")
[[ $id == "io.github.stackrats.mast" ]] || fail "manifest id is the published plugin id" "got: $id"
pass "manifest id is the published plugin id"

# The bar looks settings and IPC routes up by the id in the manifest, so the
# QML has to name the same id. Comments stripped: an assertion a commented-out
# line can satisfy passes while the widget is broken.
for file in BarWidget.qml Panel.qml; do
  stripped=$(sed 's#^\s*//.*$##' "$ROOT/$file")
  grep -qF "moduleName: \"$id\"" <<<"$stripped" || fail "$file declares the manifest id as its moduleName"
  pass "$file declares the manifest id as its moduleName"
done
stripped=$(sed 's#^\s*//.*$##' "$ROOT/BarWidget.qml")
grep -qF "target: \"$id\"" <<<"$stripped" || fail "BarWidget.qml registers the manifest id as its IPC target"
pass "BarWidget.qml registers the manifest id as its IPC target"

# Every settings key the QML reads must be declared with a default, so the
# settings panel and the code agree on what exists.
for key in refreshIntervalSec label hideWhenUnavailable mastBinary; do
  jq -e --arg k "$key" '.barWidget.defaults | has($k)' "$ROOT/manifest.json" >/dev/null \
    || fail "manifest declares a default for '$key'"
  jq -e --arg k "$key" 'any(.barWidget.schema[]; .key == $k)' "$ROOT/manifest.json" >/dev/null \
    || fail "manifest declares a schema entry for '$key'"
done
pass "every setting the widget reads has a default and a schema entry"

# The bar widget is what the shell loads; it must reach the panel, the
# service and the icon by their file names.
for file in Panel.qml Service.qml MastIcon.qml Model.js; do
  [[ -f $ROOT/$file ]] || fail "$file exists"
done
grep -qF 'Qt.resolvedUrl("Panel.qml")' "$ROOT/BarWidget.qml" || fail "BarWidget.qml loads Panel.qml"
pass "BarWidget.qml loads Panel.qml"

# Publishing requirements the marketplace checks at the repository root.
ls "$ROOT"/README* >/dev/null 2>&1 || fail "a root README exists"
ls "$ROOT"/LICENSE* >/dev/null 2>&1 || fail "a root license file exists"
pass "root README and license are present"
