#!/bin/bash
# view.sh - starts the local viewer server if needed and opens the browser,
# using the cached browser-open command from setup (self-healing if the
# cached command no longer exists on this system). Prints only URL=... and
# OPENED=yes/no for the caller to relay.
set -u

_SELF=$(realpath "$0")
_SCRIPT_DIR=$(dirname "$_SELF")
# shellcheck source=/dev/null
source "$_SCRIPT_DIR/../../../hooks/lib.sh"
corner_require_cmd python3

corner_write_skip_sentinel

mkdir -p "$CORNER_DIR/pages"
[ -f "$CORNER_DIR/pages/manifest.json" ] || echo "[]" > "$CORNER_DIR/pages/manifest.json"

if ! lsof -ti:"$SERVER_PORT" >/dev/null 2>&1; then
    cd "$CORNER_DIR" && python3 "$CORNER_DIR/server.py" --port "$SERVER_PORT" --directory "$CORNER_DIR" --bind 127.0.0.1 >/dev/null 2>&1 &
    sleep 1
fi

URL="http://localhost:$SERVER_PORT"

corner_load_env_cache
if [ -z "${BROWSER_OPEN_CMD:-}" ] || ! command -v "$BROWSER_OPEN_CMD" >/dev/null 2>&1; then
    BROWSER_OPEN_CMD=$(corner_detect_browser_cmd || true)
    {
        echo "CACHE_VERSION=1"
        echo "IS_WSL=$([ -f /proc/sys/fs/binfmt_misc/WSLInterop ] && echo yes || echo no)"
        echo "BROWSER_OPEN_CMD=$BROWSER_OPEN_CMD"
    } > "$ENV_CACHE_FILE"
fi

OPENED=no
# timeout guards against xdg-open hanging indefinitely on a headless/no-display
# system (no D-Bus session, no browser to hand off to) — never let opening the
# browser block the caller.
if [ -n "${BROWSER_OPEN_CMD:-}" ] && timeout 5 "$BROWSER_OPEN_CMD" "$URL" >/dev/null 2>&1; then
    OPENED=yes
fi

echo "URL=$URL"
echo "OPENED=$OPENED"
