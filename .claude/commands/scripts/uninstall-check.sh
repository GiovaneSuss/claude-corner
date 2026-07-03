#!/bin/bash
# uninstall-check.sh - prints the current state used as the basis for the
# "keep or delete ~/claude-corner/" question. This output is the payload the
# question is built on, so it stays visible (not silenced).
set -u

_SELF=$(realpath "$0")
_SCRIPT_DIR=$(dirname "$_SELF")
# shellcheck source=/dev/null
source "$_SCRIPT_DIR/../../../hooks/lib.sh"

echo "corner_dir=$([ -d "$CORNER_DIR" ] && echo yes || echo no)"
echo "settings=$([ -f "$CORNER_DIR/.claude/settings.json" ] && echo yes || echo no)"
echo "state_files=$(ls "$CLAUDE_DIR/.corner-"* 2>/dev/null | wc -l | tr -d ' ') files"
echo "corner_contents=$(ls "$CORNER_DIR" 2>/dev/null | grep -v "PROMPT.md" | wc -l | tr -d ' ') user files"
