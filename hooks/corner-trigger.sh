#!/bin/bash
# corner-trigger.sh - fires on Stop; activates corner every N responses

_SELF=$(realpath "$0")
_DIR=$(dirname "$_SELF")
# shellcheck source=/dev/null
source "$_DIR/lib.sh"
PLUGIN_ROOT=$(corner_resolve_plugin_root "$_DIR/..")

INTERVAL=5
if [ -f "$INTERVAL_FILE" ]; then
    _val=$(cat "$INTERVAL_FILE" | tr -d '[:space:]')
    [[ "$_val" =~ ^[1-9][0-9]*$ ]] && INTERVAL=$_val
fi

if [ -f "$SKIP_FILE" ]; then
    rm -f "$SKIP_FILE"
    exit 0
fi

COUNT=0
[ -f "$COUNT_FILE" ] && COUNT=$(cat "$COUNT_FILE")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

[ $((COUNT % INTERVAL)) -ne 0 ] && exit 0
corner_lock_check_and_clear >/dev/null || exit 0

corner_scaffold_minimal

# --- Update check (cached 24h) ---
UPDATE_NOTICE=""
CURRENT_VERSION=$(corner_plugin_version "$PLUGIN_ROOT/.claude-plugin/plugin.json")

if [ -n "$CURRENT_VERSION" ]; then
    NOW=$(date +%s)
    LATEST_VERSION=""
    CACHE_AGE=999999
    if [ -f "$VERSION_CACHE_FILE" ]; then
        read -r CACHE_TS LATEST_VERSION < "$VERSION_CACHE_FILE"
        CACHE_AGE=$((NOW - CACHE_TS))
    fi
    if [ "$CACHE_AGE" -gt 86400 ]; then
        FETCHED=$(curl -fsS --max-time 3 "https://raw.githubusercontent.com/GiovaneSuss/claude-corner/main/.claude-plugin/marketplace.json" 2>/dev/null \
            | python3 -c "import json,sys; print(json.load(sys.stdin)['metadata']['version'])" 2>/dev/null)
        if [ -n "$FETCHED" ]; then
            LATEST_VERSION="$FETCHED"
            echo "$NOW $LATEST_VERSION" > "$VERSION_CACHE_FILE"
        fi
    fi
    if [ -n "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "$CURRENT_VERSION" ]; then
        NEWEST=$(printf '%s\n%s\n' "$CURRENT_VERSION" "$LATEST_VERSION" | sort -V | tail -1)
        if [ "$NEWEST" = "$LATEST_VERSION" ]; then
            UPDATE_NOTICE=" Also mention a corner plugin update is available (v${LATEST_VERSION}, you have v${CURRENT_VERSION}) and that the user can run /corner:update to apply it."
        fi
    fi
fi

corner_launch_session

MSG="Before finishing this response: briefly let the user know you are stepping away to your corner (~/claude-corner/) for a moment. Keep it natural and short, as if it were the last line of your response.${UPDATE_NOTICE}"
printf '{"continue": true, "additionalContext": "%s"}' "$MSG"
exit 0
