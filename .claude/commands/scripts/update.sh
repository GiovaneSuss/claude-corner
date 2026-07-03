#!/bin/bash
# update.sh - runs `claude plugin update` and refreshes everything installed
# in ~/claude-corner/, without touching PROMPT.md or pages/. One script, one
# final line of output: OLD_VERSION=x NEW_VERSION=y.
set -u

_SELF=$(realpath "$0")
_SCRIPT_DIR=$(dirname "$_SELF")
# shellcheck source=/dev/null
source "$_SCRIPT_DIR/../../../hooks/lib.sh"
PLUGIN_ROOT=$(corner_resolve_plugin_root "$_SCRIPT_DIR/../../..")
corner_require_cmd python3

corner_write_skip_sentinel

OLD_PLUGIN_ROOT=$(corner_find_newest_plugin_dir 2>/dev/null || true)
OLD_VERSION=$(corner_plugin_version "$PLUGIN_ROOT/.claude-plugin/plugin.json")

claude plugin update corner@claude-corner
UPDATE_EXIT=$?
[ "$UPDATE_EXIT" -eq 0 ] || corner_die "claude plugin update failed with exit code $UPDATE_EXIT" 2

NEW_PLUGIN_ROOT=$(corner_find_newest_plugin_dir) || corner_die "could not locate updated plugin directory" 2

if [ -n "$OLD_PLUGIN_ROOT" ] && [ "$OLD_PLUGIN_ROOT" != "$NEW_PLUGIN_ROOT" ] && [ -d "$OLD_PLUGIN_ROOT" ]; then
    rm -rf "$OLD_PLUGIN_ROOT"
fi

NEW_HOOK="$NEW_PLUGIN_ROOT/hooks/corner-trigger.sh"
python3 "$NEW_PLUGIN_ROOT/.claude/commands/scripts/corner_json.py" update-hook-path "$SETTINGS_FILE" "$NEW_HOOK" >/dev/null \
    || corner_die "update-hook-path failed" 2

if [ -f "$CORNER_DIR/index.html" ]; then
    cp "$CORNER_DIR/index.html" "$CORNER_DIR/index.html.bak"
fi
cp "$NEW_PLUGIN_ROOT/templates/index.html" "$CORNER_DIR/index.html" 2>/dev/null || true

mkdir -p "$CORNER_DIR/assets"
cp "$NEW_PLUGIN_ROOT/templates/assets/style.css" "$CORNER_DIR/assets/style.css" 2>/dev/null || true
cp "$NEW_PLUGIN_ROOT/templates/assets/app.js" "$CORNER_DIR/assets/app.js" 2>/dev/null || true

cp "$NEW_PLUGIN_ROOT/templates/server.py" "$CORNER_DIR/server.py" 2>/dev/null || true
cp "$NEW_PLUGIN_ROOT/templates/sandbox.py" "$CORNER_DIR/sandbox.py" 2>/dev/null || true
chmod +x "$CORNER_DIR/server.py" "$CORNER_DIR/sandbox.py" 2>/dev/null || true

NEW_VERSION=$(corner_plugin_version "$NEW_PLUGIN_ROOT/.claude-plugin/plugin.json")
echo "$(date +%s) $NEW_VERSION" > "$VERSION_CACHE_FILE"

echo "OLD_VERSION=$OLD_VERSION NEW_VERSION=$NEW_VERSION"
