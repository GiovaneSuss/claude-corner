#!/bin/bash
# setup-scaffold.sh - creates ~/claude-corner/, copies templates, migrates
# legacy files, writes the path-confinement settings.json, and caches machine
# facts (WSL detection, browser-open command) for view.sh to reuse.
# Silent on success, except for one block of output if legacy files were
# actually migrated.
set -u

_SELF=$(realpath "$0")
_SCRIPT_DIR=$(dirname "$_SELF")
# shellcheck source=/dev/null
source "$_SCRIPT_DIR/../../../hooks/lib.sh"
PLUGIN_ROOT=$(corner_resolve_plugin_root "$_SCRIPT_DIR/../../..")
corner_require_cmd python3

corner_write_skip_sentinel

mkdir -p "$CORNER_DIR"

# Update PROMPT.md only if missing, or if it's the pre-pages legacy version.
if [ ! -f "$CORNER_DIR/PROMPT.md" ]; then
    cp "$PLUGIN_ROOT/templates/PROMPT.md" "$CORNER_DIR/PROMPT.md"
elif ! grep -q "How to save your work" "$CORNER_DIR/PROMPT.md" 2>/dev/null; then
    cp "$PLUGIN_ROOT/templates/PROMPT.md" "$CORNER_DIR/PROMPT.md"
fi

# Viewer + assets + server are versioned in the plugin — always overwrite.
cp "$PLUGIN_ROOT/templates/index.html" "$CORNER_DIR/index.html" \
    || corner_die "failed to copy index.html" 2

mkdir -p "$CORNER_DIR/assets"
cp "$PLUGIN_ROOT/templates/assets/style.css" "$CORNER_DIR/assets/style.css"
cp "$PLUGIN_ROOT/templates/assets/app.js" "$CORNER_DIR/assets/app.js"

cp "$PLUGIN_ROOT/templates/server.py" "$CORNER_DIR/server.py"
cp "$PLUGIN_ROOT/templates/sandbox.py" "$CORNER_DIR/sandbox.py"
chmod +x "$CORNER_DIR/server.py" "$CORNER_DIR/sandbox.py"

mkdir -p "$CORNER_DIR/pages"
[ -f "$CORNER_DIR/pages/manifest.json" ] || echo "[]" > "$CORNER_DIR/pages/manifest.json"

python3 "$PLUGIN_ROOT/.claude/commands/scripts/corner_json.py" migrate-legacy "$CORNER_DIR" \
    || corner_die "migrate-legacy failed" 2

python3 "$PLUGIN_ROOT/.claude/commands/scripts/corner_json.py" write-confinement "$CORNER_DIR" >/dev/null \
    || corner_die "write-confinement failed" 2

IS_WSL=no
[ -f /proc/sys/fs/binfmt_misc/WSLInterop ] && IS_WSL=yes
BROWSER_OPEN_CMD=$(corner_detect_browser_cmd || true)
{
    echo "CACHE_VERSION=1"
    echo "IS_WSL=$IS_WSL"
    echo "BROWSER_OPEN_CMD=$BROWSER_OPEN_CMD"
} > "$ENV_CACHE_FILE"
