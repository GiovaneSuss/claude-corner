#!/bin/bash
# setup-finish.sh --interval N
# Validates the chosen trigger interval, saves it, registers the Stop hook,
# and resets the prompt counter so the first corner fires after N full
# responses instead of immediately.
set -u

_SELF=$(realpath "$0")
_SCRIPT_DIR=$(dirname "$_SELF")
# shellcheck source=/dev/null
source "$_SCRIPT_DIR/../../../hooks/lib.sh"
PLUGIN_ROOT=$(corner_resolve_plugin_root "$_SCRIPT_DIR/../../..")
corner_require_cmd python3

INTERVAL=5
if [ "${1:-}" = "--interval" ] && [ -n "${2:-}" ]; then
    if [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        INTERVAL="$2"
    else
        echo "intervalo inválido '$2' — usando padrão 5"
    fi
fi

echo "$INTERVAL" > "$INTERVAL_FILE"

HOOK_CMD="$PLUGIN_ROOT/hooks/corner-trigger.sh"
python3 "$PLUGIN_ROOT/.claude/commands/scripts/corner_json.py" register-hook "$SETTINGS_FILE" "$HOOK_CMD" \
    || corner_die "register-hook failed" 2

echo "0" > "$COUNT_FILE"

echo "✓ Intervalo configurado: a cada $INTERVAL mensagens"
