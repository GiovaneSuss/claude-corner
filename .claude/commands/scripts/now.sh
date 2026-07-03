#!/bin/bash
# now.sh - activate the corner immediately, without waiting for the interval.
# Runs standalone too: `bash .claude/commands/scripts/now.sh` with or without
# CLAUDE_PLUGIN_ROOT set.
set -u

_SELF=$(realpath "$0")
_SCRIPT_DIR=$(dirname "$_SELF")
# shellcheck source=/dev/null
source "$_SCRIPT_DIR/../../../hooks/lib.sh"
PLUGIN_ROOT=$(corner_resolve_plugin_root "$_SCRIPT_DIR/../../..")

corner_write_skip_sentinel

if LOCK_PID=$(corner_lock_check_and_clear); then
    :
else
    corner_die "corner is already running (PID $LOCK_PID)"
fi

corner_scaffold_minimal
corner_launch_session

echo "Corner ativado em background. Confira ~/claude-corner/ em breve."
