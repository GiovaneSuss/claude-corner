#!/bin/bash
# lib.sh - shared constants and functions for hooks/ and .claude/commands/scripts/
# Sourced, never executed directly.

CORNER_DIR="$HOME/claude-corner"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
LOCK_FILE="$CLAUDE_DIR/.corner-lock"
COUNT_FILE="$CLAUDE_DIR/.corner-count"
INTERVAL_FILE="$CLAUDE_DIR/.corner-interval"
SKIP_FILE="$CLAUDE_DIR/.corner-skip"
VERSION_CACHE_FILE="$CLAUDE_DIR/.corner-version-check"
ENV_CACHE_FILE="$CORNER_DIR/.corner-env"
CORNER_LOCK_TTL=360
SERVER_PORT=8765

corner_die() {
    echo "ERROR: $1" >&2
    exit "${2:-1}"
}

corner_require_cmd() {
    command -v "$1" >/dev/null 2>&1 || corner_die "required command not found: $1" 2
}

# Resolves PLUGIN_ROOT via $CLAUDE_PLUGIN_ROOT, falling back to the path passed
# in (computed by the caller relative to its own script location). Validates
# the result actually looks like the plugin repo before returning it.
corner_resolve_plugin_root() {
    local fallback="$1"
    local root="${CLAUDE_PLUGIN_ROOT:-$fallback}"
    root=$(cd "$root" 2>/dev/null && pwd) || corner_die "cannot resolve plugin root (tried: $root)" 2
    [ -d "$root/templates" ] || corner_die "invalid plugin root: $root/templates missing" 2
    [ -f "$root/.claude-plugin/plugin.json" ] || corner_die "invalid plugin root: $root/.claude-plugin/plugin.json missing" 2
    printf '%s' "$root"
}

corner_write_skip_sentinel() {
    echo "" > "$SKIP_FILE"
}

# Pure read: true (echoes PID) if a session is running, false otherwise.
# Never mutates the lock file — safe for status.sh.
corner_lock_is_active() {
    [ -f "$LOCK_FILE" ] || return 1
    local pid ts now
    read -r pid ts < "$LOCK_FILE"
    now=$(date +%s)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ $(( now - ${ts:-0} )) -lt "$CORNER_LOCK_TTL" ]; then
        echo "$pid"
        return 0
    fi
    return 1
}

# Mutating version: clears a stale lock file. Returns 0 (free to proceed) or
# 1 with the busy PID on stdout.
corner_lock_check_and_clear() {
    if [ -f "$LOCK_FILE" ]; then
        local pid ts now
        read -r pid ts < "$LOCK_FILE"
        now=$(date +%s)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ $(( now - ${ts:-0} )) -lt "$CORNER_LOCK_TTL" ]; then
            echo "$pid"
            return 1
        fi
        rm -f "$LOCK_FILE"
    fi
    return 0
}

corner_find_newest_plugin_dir() {
    local d
    d=$(ls -d "$CLAUDE_DIR/plugins/cache/claude-corner/corner/"*/ 2>/dev/null | sort -V | tail -1 | sed 's|/$||')
    [ -n "$d" ] || corner_die "no installed plugin version directory found" 2
    printf '%s' "$d"
}

corner_load_env_cache() {
    # shellcheck source=/dev/null
    [ -f "$ENV_CACHE_FILE" ] && source "$ENV_CACHE_FILE"
}

corner_detect_browser_cmd() {
    if command -v wslview >/dev/null 2>&1; then echo wslview; return 0; fi
    if command -v xdg-open >/dev/null 2>&1; then echo xdg-open; return 0; fi
    if command -v explorer.exe >/dev/null 2>&1; then echo explorer.exe; return 0; fi
    return 1
}

corner_plugin_version() {
    python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$1" 2>/dev/null
}

# Requires PLUGIN_ROOT already set/validated.
corner_scaffold_minimal() {
    mkdir -p "$CORNER_DIR"
    if [ ! -f "$CORNER_DIR/PROMPT.md" ]; then
        cp "$PLUGIN_ROOT/templates/PROMPT.md" "$CORNER_DIR/PROMPT.md"
    fi
    if [ ! -f "$CORNER_DIR/index.html" ]; then
        cp "$PLUGIN_ROOT/templates/index.html" "$CORNER_DIR/index.html" 2>/dev/null || true
    fi
    mkdir -p "$CORNER_DIR/pages"
    [ -f "$CORNER_DIR/pages/manifest.json" ] || echo "[]" > "$CORNER_DIR/pages/manifest.json"
}

# Launches the confined free-time session in the background and registers the
# lock file, exactly like the old duplicated now.sh/corner-trigger.sh blocks.
# After the session ends (success, error, or timeout), it runs corner_json.py
# sync-manifest so any folder Claude created gets registered even if the
# session never got a chance to (or Claude never touches manifest.json at
# all anymore) — then releases the lock.
# Requires PLUGIN_ROOT and CORNER_DIR already scaffolded.
corner_launch_session() {
    local full_prompt
    full_prompt=$(bash "$PLUGIN_ROOT/hooks/corner-prompt.sh" "$CORNER_DIR")
    local corner_json="$PLUGIN_ROOT/.claude/commands/scripts/corner_json.py"

    export _CORNER_PROMPT="$full_prompt"
    nohup bash -c "
      cd \"$CORNER_DIR\"
      timeout 300 claude --allowedTools 'Read,Write,Edit' --max-turns 15 -p \"\$_CORNER_PROMPT\"
      python3 \"$corner_json\" sync-manifest \"$CORNER_DIR\" >/dev/null 2>&1
      rm -f \"$LOCK_FILE\"
    " >/dev/null 2>&1 &
    local bg_pid=$!
    echo "$bg_pid $(date +%s)" > "$LOCK_FILE"
    disown "$bg_pid"
    unset _CORNER_PROMPT
}
