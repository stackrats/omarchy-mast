#!/bin/bash

# Checks a plugin folder the way `omarchy plugin validate` does, so CI can
# refuse a manifest the shell would reject without needing Omarchy installed.
# Same rules: schemaVersion 1, required fields, an entry point for every kind
# that needs one, safe relative entry points that exist, no symlinks, and an
# id outside the reserved omarchy.* namespace. Exits 0 when valid.

set -o pipefail

fail() {
  echo "validate: $*" >&2
  exit 1
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  echo "Usage: scripts/validate.sh [plugin-folder]   (defaults to the repository root)"
  exit 0
fi

PLUGIN_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -d $PLUGIN_DIR ]] || fail "plugin folder not found: $PLUGIN_DIR"
command -v jq >/dev/null || fail "jq is required"

MANIFEST="$PLUGIN_DIR/manifest.json"
[[ -f $MANIFEST ]] || fail "missing manifest.json in $PLUGIN_DIR"
jq -e . "$MANIFEST" >/dev/null 2>&1 || fail "manifest.json is not valid JSON"

jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null 2>&1 \
  || fail "schemaVersion must be the number 1"

for field in id name version author description kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "manifest missing required field '$field'"
done

for field in id name version author description; do
  jq -e --arg f "$field" '(.[$f] | type) == "string" and ((.[$f] | length) > 0)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "manifest field '$field' must be a non-empty string"
done

ID=$(jq -r '.id' "$MANIFEST")
[[ $ID =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "invalid plugin id '$ID' (lowercase letters, digits, . _ - only)"
[[ $ID != *".."* ]] || fail "invalid plugin id '$ID'"
[[ $ID != omarchy.* ]] || fail "plugin id '$ID' uses the reserved omarchy.* namespace"

jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'kinds' must be a non-empty array"
jq -e '[.kinds[] | select(. as $k | ["bar", "bar-widget", "menu", "overlay", "panel", "service"] | index($k) | not)] | length == 0' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'kinds' contains an unsupported kind"

jq -e '(.entryPoints | type) == "object"' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'entryPoints' must be an object"

jq -e '
  if ((.barWidget? | type) == "object" and (.barWidget | has("defaultSection"))) then
    .barWidget.defaultSection as $section
    | ($section | type) == "string"
      and (["left", "center", "right"] | index($section)) != null
  else true end
' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'barWidget.defaultSection' must be left, center, or right"

while IFS= read -r ep_json; do
  [[ -n $ep_json ]] || continue
  ep=$(jq -r '.' <<<"$ep_json")
  [[ -n $ep ]] || fail "entry point path is empty"
  [[ $ep != *$'\n'* ]] || fail "entry point may not contain a newline"
  [[ $ep != /* ]] || fail "entry point must be a relative path: '$ep'"
  [[ $ep != *".."* ]] || fail "entry point may not contain '..': '$ep'"
  [[ -f "$PLUGIN_DIR/$ep" ]] || fail "entry point file not found: '$ep'"
done < <(jq -c '.entryPoints | to_entries[] | .value' "$MANIFEST")

for kind_entry_point in "bar:bar" "bar-widget:barWidget" "menu:menu" "overlay:overlay" "panel:panel" "service:service"; do
  kind="${kind_entry_point%%:*}"
  entry_point="${kind_entry_point##*:}"
  jq -e --arg kind "$kind" '(.kinds | index($kind)) != null' "$MANIFEST" >/dev/null 2>&1 || continue
  jq -e --arg ep "$entry_point" '.entryPoints | has($ep)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "kind '$kind' requires an 'entryPoints.$entry_point' to load"
done

link=$(find "$PLUGIN_DIR" -name .git -prune -o -type l -print -quit 2>/dev/null)
[[ -z $link ]] || fail "symlinks are not allowed inside a plugin folder: $link"

echo "valid: $ID $(jq -r '.version' "$MANIFEST") ($(jq -r '.kinds | join(",")' "$MANIFEST"))"
exit 0
