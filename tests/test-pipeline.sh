#!/bin/bash
# test-pipeline.sh - end-to-end regression test for the corner scripts.
#
# Runs the real setup -> now -> corner-trigger -> status -> uninstall pipeline
# against a throwaway $HOME under /tmp (never the real ~/.claude or
# ~/claude-corner) and asserts the concrete result of each step, not just
# "did it exit 0". A fake `claude` CLI is put on PATH so this costs no real
# API call and finishes in seconds instead of minutes.
#
# Not covered on purpose: update.sh (would need a fake nested plugin-cache
# version-directory tree to be meaningful — low value for the complexity;
# exercise it manually before a release per CLAUDE.md's verification list)
# and the actual creative behavior of a real Claude session inside the
# sandbox (that's qualitative, not scriptable).
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_ROOT/.claude/commands/scripts"

TEST_HOME=$(mktemp -d /tmp/corner-test-pipeline.XXXXXX)
FAKE_BIN="$TEST_HOME/bin"
mkdir -p "$TEST_HOME/.claude" "$FAKE_BIN"

VIEW_SERVER_PID=""
cleanup() {
    [ -n "$VIEW_SERVER_PID" ] && kill "$VIEW_SERVER_PID" 2>/dev/null
    rm -rf "$TEST_HOME"
}
trap cleanup EXIT

PASS=0
FAIL=0
SKIP=0
FAILED_NAMES=()

ok()   { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  FAIL - $1"; [ -n "${2:-}" ] && echo "         -> $2"; }
skip() { SKIP=$((SKIP+1)); echo "  skip - $1 ($2)"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    [ "$expected" = "$actual" ] && ok "$desc" || bad "$desc" "expected [$expected], got [$actual]"
}

assert_exit() {
    local desc="$1" expected="$2" actual="$3"
    [ "$expected" = "$actual" ] && ok "$desc (exit $actual)" || bad "$desc" "expected exit $expected, got $actual"
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    printf '%s' "$haystack" | grep -qF "$needle" && ok "$desc" || bad "$desc" "expected to find [$needle] in: $haystack"
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    printf '%s' "$haystack" | grep -qF "$needle" && bad "$desc" "did not expect to find [$needle]" || ok "$desc"
}

assert_file_exists() {
    local desc="$1" path="$2"
    [ -e "$path" ] && ok "$desc" || bad "$desc" "missing: $path"
}

assert_json_valid() {
    local desc="$1" path="$2"
    python3 -c "import json; json.load(open('$path'))" 2>/dev/null && ok "$desc" || bad "$desc" "invalid JSON: $path"
}

# Runs a command with the isolated HOME/PATH/PLUGIN_ROOT; sets $OUT and $CODE.
# Hard-capped at 30s so any unexpected hang fails the test instead of hanging
# the whole suite forever. Captures via a real file, not `$(...)`: a script
# that backgrounds a listening-socket server (view.sh starting server.py)
# leaves that fd attached to a pipe forever, so `$(...)` never sees EOF even
# after the foreground script exits. A plain file redirect has no such
# wait-for-every-writer semantics.
run() {
    local outfile
    outfile=$(mktemp)
    HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" timeout 30 "$@" > "$outfile" 2>&1
    CODE=$?
    OUT=$(cat "$outfile")
    rm -f "$outfile"
}

wait_for_lock_clear() {
    local timeout="${1:-10}" start=$SECONDS
    while [ -f "$TEST_HOME/.claude/.corner-lock" ]; do
        [ $((SECONDS - start)) -ge "$timeout" ] && return 1
        sleep 0.2
    done
    return 0
}

manifest_count() {
    python3 -c "import json; print(len(json.load(open('$1'))))" 2>/dev/null
}

CORNER_DIR="$TEST_HOME/claude-corner"
MANIFEST="$CORNER_DIR/pages/manifest.json"

# Fake `claude` CLI: instead of a real session, deterministically drops one
# new page per invocation (unique folder name), mimicking what a real
# free-time session leaves behind for sync-manifest to pick up.
cat > "$FAKE_BIN/claude" <<'EOF'
#!/bin/bash
folder="fake-session-$(date +%s%N)"
mkdir -p "$PWD/pages/$folder"
echo "test content" > "$PWD/pages/$folder/index.md"
exit 0
EOF
chmod +x "$FAKE_BIN/claude"

echo "=== 1. setup-scaffold.sh (clean install) ==="
run bash "$SCRIPTS/setup-scaffold.sh"
assert_exit "setup-scaffold exits 0" 0 "$CODE"
assert_file_exists "PROMPT.md created" "$CORNER_DIR/PROMPT.md"
assert_file_exists "index.html created" "$CORNER_DIR/index.html"
assert_file_exists "assets/style.css created" "$CORNER_DIR/assets/style.css"
assert_file_exists "assets/app.js created" "$CORNER_DIR/assets/app.js"
assert_file_exists "server.py created" "$CORNER_DIR/server.py"
assert_file_exists "sandbox.py created" "$CORNER_DIR/sandbox.py"
[ -x "$CORNER_DIR/server.py" ] && ok "server.py is executable" || bad "server.py is executable"
assert_file_exists "pages/manifest.json created" "$MANIFEST"
assert_json_valid "manifest.json is valid JSON" "$MANIFEST"
assert_eq "manifest.json starts empty" "0" "$(manifest_count "$MANIFEST")"
assert_file_exists "confinement settings.json created" "$CORNER_DIR/.claude/settings.json"
assert_json_valid "confinement settings.json is valid JSON" "$CORNER_DIR/.claude/settings.json"
CONFINEMENT=$(cat "$CORNER_DIR/.claude/settings.json")
assert_contains "confinement scopes Read to corner dir" "$CONFINEMENT" "Read($CORNER_DIR/**)"
assert_contains "confinement scopes Write to corner dir" "$CONFINEMENT" "Write($CORNER_DIR/**)"
assert_contains "confinement scopes Edit to corner dir" "$CONFINEMENT" "Edit($CORNER_DIR/**)"
assert_file_exists ".corner-env cache written" "$CORNER_DIR/.corner-env"
assert_contains ".corner-env has CACHE_VERSION" "$(cat "$CORNER_DIR/.corner-env")" "CACHE_VERSION=1"

echo ""
echo "=== 2. setup-finish.sh --interval 7 ==="
run bash "$SCRIPTS/setup-finish.sh" --interval 7
assert_exit "setup-finish exits 0" 0 "$CODE"
assert_eq "interval saved as 7" "7" "$(cat "$TEST_HOME/.claude/.corner-interval")"
assert_eq "counter reset to 0" "0" "$(cat "$TEST_HOME/.claude/.corner-count")"
SETTINGS=$(cat "$TEST_HOME/.claude/settings.json")
assert_contains "Stop hook registered with correct path" "$SETTINGS" "$REPO_ROOT/hooks/corner-trigger.sh"

echo ""
echo "=== 3. setup-finish.sh --interval bogus (invalid -> falls back to 5) ==="
run bash "$SCRIPTS/setup-finish.sh" --interval bogus
assert_exit "setup-finish exits 0 even on invalid interval" 0 "$CODE"
assert_contains "warns about invalid interval" "$OUT" "inválido"
assert_eq "falls back to interval 5" "5" "$(cat "$TEST_HOME/.claude/.corner-interval")"

echo ""
echo "=== 4. now.sh — rejects when a session is genuinely running ==="
echo "$$ $(date +%s)" > "$TEST_HOME/.claude/.corner-lock"
run bash "$SCRIPTS/now.sh"
assert_exit "now.sh exits 1 when busy" 1 "$CODE"
assert_contains "now.sh reports the busy PID" "$OUT" "ERROR: corner is already running (PID $$)"
assert_eq "busy lock file left untouched" "$$" "$(cut -d' ' -f1 "$TEST_HOME/.claude/.corner-lock")"
rm -f "$TEST_HOME/.claude/.corner-lock"

echo ""
echo "=== 5. now.sh — clears a stale lock, launches, syncs the manifest ==="
echo "999999 100" > "$TEST_HOME/.claude/.corner-lock"
BEFORE_COUNT=$(manifest_count "$MANIFEST")
run bash "$SCRIPTS/now.sh"
assert_exit "now.sh exits 0" 0 "$CODE"
assert_contains "now.sh confirms activation" "$OUT" "ativado em background"
if wait_for_lock_clear 10; then
    ok "lock released after session completed"
else
    bad "lock released after session completed" "still present after 10s timeout"
fi
AFTER_COUNT=$(manifest_count "$MANIFEST")
assert_eq "sync-manifest registered exactly one new page" "$((BEFORE_COUNT + 1))" "$AFTER_COUNT"
LAST_ENTRY=$(python3 -c "import json; e=json.load(open('$MANIFEST'))[-1]; print(e['folder'], e['entry'], e['type'])")
assert_contains "new entry has the right entry file" "$LAST_ENTRY" "index.md"
assert_contains "new entry's type inferred as 'writing' for a plain .md" "$LAST_ENTRY" "writing"

echo ""
echo "=== 6. status.sh ==="
run bash "$SCRIPTS/status.sh"
assert_exit "status.sh exits 0" 0 "$CODE"
assert_contains "reports not running" "$OUT" "running: não"
assert_contains "reports prompt count" "$OUT" "total_prompts:"
assert_not_contains "no creations placeholder should be gone" "$OUT" "(nenhuma criação ainda)"

echo ""
echo "=== 7. corner-trigger.sh — skip sentinel prevents counting ==="
echo "" > "$TEST_HOME/.claude/.corner-skip"
COUNT_BEFORE=$(cat "$TEST_HOME/.claude/.corner-count")
run bash "$REPO_ROOT/hooks/corner-trigger.sh"
assert_exit "corner-trigger exits 0 on sentinel" 0 "$CODE"
assert_eq "sentinel file consumed" "no" "$([ -f "$TEST_HOME/.claude/.corner-skip" ] && echo yes || echo no)"
assert_eq "counter untouched by a sentineled call" "$COUNT_BEFORE" "$(cat "$TEST_HOME/.claude/.corner-count")"

echo ""
echo "=== 8. corner-trigger.sh — counts up, only fires at the interval ==="
echo "2" > "$TEST_HOME/.claude/.corner-interval"
echo "0" > "$TEST_HOME/.claude/.corner-count"
CURRENT_VERSION=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['version'])")
echo "$(date +%s) $CURRENT_VERSION" > "$TEST_HOME/.claude/.corner-version-check"  # skip the network update-check

run bash "$REPO_ROOT/hooks/corner-trigger.sh"
assert_exit "1st call (count=1) exits 0" 0 "$CODE"
assert_eq "1st call doesn't fire (no JSON output)" "" "$OUT"
assert_eq "counter now at 1" "1" "$(cat "$TEST_HOME/.claude/.corner-count")"

BEFORE_COUNT=$(manifest_count "$MANIFEST")
run bash "$REPO_ROOT/hooks/corner-trigger.sh"
assert_exit "2nd call (count=2) exits 0" 0 "$CODE"
assert_eq "counter now at 2" "2" "$(cat "$TEST_HOME/.claude/.corner-count")"
if printf '%s' "$OUT" | python3 -c "import json,sys; json.loads(sys.stdin.read())" 2>/dev/null; then
    ok "2nd call prints valid JSON when it fires"
else
    bad "2nd call prints valid JSON when it fires" "got: $OUT"
fi
assert_contains "fired call mentions stepping away to the corner" "$OUT" "stepping away to your corner"

if wait_for_lock_clear 10; then
    ok "lock released after triggered session completed"
else
    bad "lock released after triggered session completed" "still present after 10s timeout"
fi
AFTER_COUNT=$(manifest_count "$MANIFEST")
assert_eq "triggered session's page got synced to the manifest" "$((BEFORE_COUNT + 1))" "$AFTER_COUNT"

echo ""
echo "=== 9. view.sh (guarded — skipped if port 8765 is already in use) ==="
if lsof -ti:8765 >/dev/null 2>&1; then
    skip "view.sh live server check" "port 8765 already in use, not touching it"
else
    run bash "$SCRIPTS/view.sh"
    assert_exit "view.sh exits 0" 0 "$CODE"
    assert_contains "view.sh prints the URL" "$OUT" "URL=http://localhost:8765"
    assert_contains "view.sh reports OPENED status" "$OUT" "OPENED="
    VIEW_SERVER_PID=$(lsof -ti:8765 2>/dev/null | head -1)
    if [ -n "$VIEW_SERVER_PID" ]; then
        ok "view.sh actually started a server on 8765"
    else
        bad "view.sh actually started a server on 8765" "no process found listening"
    fi
fi

echo ""
echo "=== 10. corner_json.py — invalid JSON is refused, not corrupted further ==="
BROKEN="$TEST_HOME/.claude/broken-settings.json"
echo '{ this is not json' > "$BROKEN"
set +e
OUT=$(python3 "$SCRIPTS/corner_json.py" remove-hook "$BROKEN" 2>&1)
CODE=$?
set -e
assert_exit "invalid JSON causes exit 2" 2 "$CODE"
assert_contains "invalid JSON produces an ERROR message" "$OUT" "ERROR: invalid JSON"
assert_eq "broken file was not modified" "{ this is not json" "$(cat "$BROKEN")"

echo ""
echo "=== 11. corner_json.py — missing optional file is a no-op success ==="
set +e
OUT=$(python3 "$SCRIPTS/corner_json.py" remove-installed-plugin "$TEST_HOME/.claude/does-not-exist.json" 2>&1)
CODE=$?
set -e
assert_exit "missing optional file exits 0" 0 "$CODE"
assert_contains "reports no-op clearly" "$OUT" "Nenhuma entrada"

echo ""
echo "=== 12. uninstall-check.sh ==="
run bash "$SCRIPTS/uninstall-check.sh"
assert_exit "uninstall-check exits 0" 0 "$CODE"
assert_contains "reports corner_dir=yes" "$OUT" "corner_dir=yes"
assert_contains "reports settings=yes" "$OUT" "settings=yes"

echo ""
echo "=== 13. uninstall-purge.sh (keep corner dir) ==="
run bash "$SCRIPTS/uninstall-purge.sh"
assert_exit "uninstall-purge exits 0" 0 "$CODE"
assert_eq "corner dir kept" "yes" "$([ -d "$CORNER_DIR" ] && echo yes || echo no)"
assert_not_contains "Stop hook actually removed from settings.json" "$(cat "$TEST_HOME/.claude/settings.json")" "corner-trigger.sh"
assert_eq "state files all gone" "0" "$(ls "$TEST_HOME/.claude/.corner-"* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "confinement settings.json gone" "no" "$([ -f "$CORNER_DIR/.claude/settings.json" ] && echo yes || echo no)"

echo ""
echo "=== 14. uninstall-purge.sh --delete-corner-dir ==="
run bash "$SCRIPTS/uninstall-purge.sh" --delete-corner-dir
assert_exit "uninstall-purge --delete-corner-dir exits 0" 0 "$CODE"
assert_eq "corner dir removed" "no" "$([ -d "$CORNER_DIR" ] && echo yes || echo no)"

echo ""
echo "=== Resultado ==="
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
if [ "$FAIL" -gt 0 ]; then
    echo "Falharam:"
    for name in "${FAILED_NAMES[@]}"; do echo "  - $name"; done
    exit 1
fi
exit 0
