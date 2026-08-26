#!/bin/bash
# Standalone reimplementation of Omarchy's `omarchy plugin validate` checks
# (see /usr/share/omarchy/bin/omarchy-plugin-validate on an Omarchy system),
# so CI can catch a broken manifest without needing Omarchy installed.
# When you have Omarchy installed, `omarchy plugin validate .` is the
# authoritative check — this is a best-effort mirror of it for CI.
set -o pipefail

fail() {
  echo "validate-manifest: $*" >&2
  exit 1
}

PLUGIN_DIR="${1:-.}"
[[ -d "$PLUGIN_DIR" ]] || fail "plugin folder not found: $PLUGIN_DIR"

MANIFEST="$PLUGIN_DIR/manifest.json"
[[ -f "$MANIFEST" ]] || fail "missing manifest.json in $PLUGIN_DIR"
jq -e . "$MANIFEST" >/dev/null 2>&1 || fail "manifest.json is not valid JSON"

jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null 2>&1 \
  || fail "unsupported or missing schemaVersion (expected 1)"

for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "manifest missing required field '$field'"
done

ID=$(jq -r '.id // ""' "$MANIFEST")
[[ -n "$ID" ]] || fail "manifest 'id' is empty"
[[ "$ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid plugin id '$ID'"
[[ "$ID" != *".."* ]] || fail "invalid plugin id '$ID'"
[[ "$ID" != omarchy.* ]] || fail "plugin id '$ID' uses the reserved omarchy.* namespace"

jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'kinds' must be a non-empty array"

jq -e '(.entryPoints | type) == "object"' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'entryPoints' must be an object"

while IFS= read -r ep_json; do
  [[ -n "$ep_json" ]] || continue
  ep=$(jq -r '.' <<<"$ep_json")
  [[ -n "$ep" ]] || fail "entry point path is empty"
  [[ "$ep" != /* ]] || fail "entry point must be a relative path: '$ep'"
  [[ "$ep" != *".."* ]] || fail "entry point may not contain '..': '$ep'"
  [[ -f "$PLUGIN_DIR/$ep" ]] || fail "entry point file not found: '$ep'"
done < <(jq -c '.entryPoints | to_entries[] | .value' "$MANIFEST")

for kind_entry_point in \
  "bar:bar" \
  "bar-widget:barWidget" \
  "menu:menu" \
  "overlay:overlay" \
  "panel:panel" \
  "service:service"; do
  kind="${kind_entry_point%%:*}"
  entry_point="${kind_entry_point##*:}"
  jq -e --arg kind "$kind" '(.kinds | index($kind)) != null' "$MANIFEST" >/dev/null 2>&1 || continue
  jq -e --arg ep "$entry_point" '.entryPoints | has($ep)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "kind '$kind' requires an 'entryPoints.$entry_point' to load"
done

link=$(find "$PLUGIN_DIR" -name .git -prune -o -type l -print -quit 2>/dev/null)
[[ -z "$link" ]] || fail "symlinks are not allowed inside a plugin folder: $link"

echo "manifest.json is valid"
