#!/bin/bash
# uninstall-purge.sh [--delete-corner-dir]
# Removes everything /corner:setup created except the decision on the corner
# folder itself, which is controlled by the flag. Each removal is isolated —
# one failing does not abort the others. Exit 3 on partial failure, with one
# "ERROR: <step> — <reason>" line per failed step.
set -u

_SELF=$(realpath "$0")
_SCRIPT_DIR=$(dirname "$_SELF")
# shellcheck source=/dev/null
source "$_SCRIPT_DIR/../../../hooks/lib.sh"
corner_require_cmd python3

DELETE_CORNER_DIR=no
[ "${1:-}" = "--delete-corner-dir" ] && DELETE_CORNER_DIR=yes

FAILED=0
fail() {
    echo "ERROR: $1" >&2
    FAILED=1
}

python3 "$_SCRIPT_DIR/corner_json.py" remove-hook "$SETTINGS_FILE" \
    || fail "remove Stop hook — corner_json.py failed"

rm -f "$COUNT_FILE" "$LOCK_FILE" "$CLAUDE_DIR/.corner-done" "$INTERVAL_FILE" \
      "$VERSION_CACHE_FILE" "$SKIP_FILE" \
    || fail "remove state files"

rm -f "$CORNER_DIR/.claude/settings.json" || fail "remove confinement settings.json"
rmdir "$CORNER_DIR/.claude" 2>/dev/null || true

rm -rf "$CLAUDE_DIR/plugins/cache/claude-corner" || fail "remove plugin cache"

python3 "$_SCRIPT_DIR/corner_json.py" remove-plugin-registry "$SETTINGS_FILE" \
    || fail "remove plugin registry entries — corner_json.py failed"

python3 "$_SCRIPT_DIR/corner_json.py" remove-installed-plugin "$CLAUDE_DIR/plugins/installed_plugins.json" \
    || fail "remove installed_plugins.json entry — corner_json.py failed"

python3 "$_SCRIPT_DIR/corner_json.py" remove-known-marketplace "$CLAUDE_DIR/plugins/known_marketplaces.json" \
    || fail "remove known_marketplaces.json entry — corner_json.py failed"

rm -rf "$CLAUDE_DIR/plugins/marketplaces/claude-corner" || fail "remove marketplace clone"
rm -rf "$CLAUDE_DIR/corner-hooks" || fail "remove legacy hooks directory"

if [ "$DELETE_CORNER_DIR" = "yes" ]; then
    rm -rf "$CORNER_DIR" || fail "remove ~/claude-corner"
fi

[ "$FAILED" -eq 0 ] || exit 3
exit 0
