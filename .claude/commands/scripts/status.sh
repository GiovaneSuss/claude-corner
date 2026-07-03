#!/bin/bash
# status.sh - shows the corner's history. This output IS the point of the
# command, so it stays visible. Uses corner_lock_is_active (pure read) since
# a status check should never have the side effect of clearing a lock.
set -u

_SELF=$(realpath "$0")
_SCRIPT_DIR=$(dirname "$_SELF")
# shellcheck source=/dev/null
source "$_SCRIPT_DIR/../../../hooks/lib.sh"
corner_require_cmd python3
corner_write_skip_sentinel

echo "=== Corner Status ==="
echo "pasta: $CORNER_DIR"

RUNNING="não"
if PID=$(corner_lock_is_active); then
    RUNNING="sim (PID $PID)"
fi
echo "running: $RUNNING"
echo "total_prompts: $(cat "$COUNT_FILE" 2>/dev/null || echo 0)"
echo ""
echo "=== Criações ==="
if [ -f "$CORNER_DIR/pages/manifest.json" ]; then
    python3 "$_SCRIPT_DIR/corner_json.py" list-manifest "$CORNER_DIR/pages/manifest.json"
else
    echo "(pasta não existe ainda — rode /corner:setup)"
fi
