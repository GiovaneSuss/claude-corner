# CLAUDE.md — Development Rules for claude-corner

This file is for development only. It documents the invariants and patterns that must be followed when modifying this plugin.

---

## Core invariant: never modify ~/.claude/ directly

All changes go into this repo. The installed plugin in `~/.claude/plugins/cache/claude-corner/` is updated via `/corner:update`, which replaces the old version directory with the new one. Never hand-edit files in `~/.claude/`.

---

## Sentinel file — preventing counter pollution from corner commands

**File:** `~/.claude/.corner-skip`

Every corner script that isn't a pure read (`now.sh`, `setup-scaffold.sh`, `view.sh`, `status.sh`, `update.sh`) writes the sentinel at the very start via `corner_write_skip_sentinel` (`hooks/lib.sh`):

```bash
corner_write_skip_sentinel   # echo "" > "$SKIP_FILE"
```

The Stop hook (`corner-trigger.sh`) checks for it BEFORE incrementing the counter (via the `SKIP_FILE` constant from `lib.sh`):

```bash
if [ -f "$SKIP_FILE" ]; then
    rm -f "$SKIP_FILE"
    exit 0
fi
```

**Why:** The Stop hook fires after every Claude response, including responses to corner commands. Without the sentinel, running `/corner:now` when the counter is at N-1 would both launch a corner session (from `now.sh`) AND trigger the auto-activation (from the Stop hook), resulting in two concurrent sessions. The sentinel ensures corner command responses never count toward the interval.

**Rule:** The counter is incremented ONLY by `corner-trigger.sh`. No script ever increments it directly.

---

## Prompt: always via corner-prompt.sh, always identical

`hooks/corner-prompt.sh` is the single source of truth for the corner prompt. It's called from exactly one place now: `corner_launch_session()` in `hooks/lib.sh`, used by both `corner-trigger.sh` and `now.sh`. No script builds the prompt any other way.

The prompt always includes the history section — even on the first session when the manifest is empty — plus a compact list of existing `pages/*` folders (capped at 30) so Claude knows what already exists without reading `manifest.json` itself. `corner-prompt.sh` must never silently exit without outputting the dynamic context block.

---

## Shell quoting: nohup bash -c with the prompt

Never interpolate the full prompt directly into a `bash -c "..."` string — `PROMPT.md` contains double quotes that will break the string. This is why the nohup/lock/launch pattern lives in exactly one place, `corner_launch_session()` in `hooks/lib.sh`:

```bash
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
```

`\$_CORNER_PROMPT` prevents expansion during string construction; the subshell reads the exported env var at runtime. **Never duplicate this block elsewhere** — call `corner_launch_session` instead. The `sync-manifest` step after `claude -p` returns is what registers whatever Claude created in `pages/*/` into `manifest.json`; Claude itself never touches that file (see "Free-time session" below).

---

## Lock file format

`~/.claude/.corner-lock` contains: `PID TIMESTAMP` (space-separated).

Validation checks:
1. Process is alive: `kill -0 $LOCK_PID 2>/dev/null`
2. Age is under `$CORNER_LOCK_TTL` seconds (360, defined in `hooks/lib.sh`)

If either fails, the lock is stale. Two functions in `hooks/lib.sh` implement this check with different side effects:
- `corner_lock_is_active` — pure read, no mutation. Used by `status.sh`, which must never clear a lock as a side effect of a status check.
- `corner_lock_check_and_clear` — deletes a stale lock file before returning. Used by `now.sh` and `corner-trigger.sh`, which are actually about to launch a session and need the stale lock out of the way.

---

## Shared library: hooks/lib.sh

`hooks/lib.sh` holds every constant (`CORNER_DIR`, `SETTINGS_FILE`, `LOCK_FILE`, `COUNT_FILE`, `INTERVAL_FILE`, `SKIP_FILE`, `VERSION_CACHE_FILE`, `ENV_CACHE_FILE`, `CORNER_LOCK_TTL`, `SERVER_PORT`) and every function shared between `hooks/corner-trigger.sh` and `.claude/commands/scripts/*.sh`. It lives in `hooks/` (not `commands/scripts/`) because it's genuinely shared runtime logic, and putting it in `commands/scripts/` would make `hooks/` reach into `commands/` — an inverted dependency.

Any script that sources it resolves `PLUGIN_ROOT` itself first, via `corner_resolve_plugin_root <fallback>`, where `<fallback>` is a path computed relative to the calling script's own location (`$CLAUDE_PLUGIN_ROOT` always wins when set). This function also validates the result actually looks like the plugin repo (`templates/` and `.claude-plugin/plugin.json` must exist) before returning it — a wrong/missing `PLUGIN_ROOT` fails loudly instead of silently copying from nowhere.

**Never duplicate a `lib.sh` function's logic inline in a script.** If a command script needs lock handling, scaffold creation, or session launch, it sources `lib.sh` and calls the function — this is the entire point of the refactor that introduced it.

---

## Command scripts: .claude/commands/scripts/

Each of the 6 slash commands (`now`, `setup`, `status`, `update`, `uninstall`, `view`) is a thin `.md` wrapper around one or two dedicated scripts in `.claude/commands/scripts/`. The `.md` file keeps only what genuinely requires Claude's judgment or an interactive tool (`AskUserQuestion`, reading and describing the latest creation in `status.md`) — everything mechanical and deterministic lives in the script.

**Exit code contract:** `0` success, `1` expected failure (e.g. lock busy), `2` environment/precondition failure, `3` partial failure (uninstall — some steps succeeded, some didn't). Every error goes to stderr as `ERROR: <message>` via `corner_die`. Every `.md` instructs Claude: if the script prints `ERROR:` or exits non-zero, relay it — never assume success.

**Silence convention:** scripts are silent on success except where the output IS the point of the command (`status.sh`'s history listing, `uninstall-check.sh`'s state dump that the following `AskUserQuestion` is based on, `update.sh`'s final `OLD_VERSION=x NEW_VERSION=y` line).

All JSON mutation goes through `.claude/commands/scripts/corner_json.py` — never a one-off `python3 -c` embedded in a script. It writes atomically (`.tmp` + `os.replace`) and treats a missing-but-optional file (e.g. `settings.json` on a clean install) as a no-op success rather than a crash; only invalid JSON in a file that must exist is a hard error. See `.claude/commands/scripts/README.md` for the full subcommand reference.

---

## Free-time session: Claude never touches manifest.json

The confined session (`Read,Write,Edit` only, driven by `templates/PROMPT.md`) creates a folder under `pages/{slug}/` and files inside it — nothing else. It never reads or edits `pages/manifest.json`. Two things make this possible:

1. `corner-prompt.sh` injects the list of existing `pages/*` folders (folder — title, capped at 30) directly into the prompt, so Claude doesn't need to read the manifest to know what already exists.
2. After `claude -p` returns — success, error, or timeout — `corner_launch_session()` runs `corner_json.py sync-manifest "$CORNER_DIR"` before releasing the lock. This scans `pages/*/` for folders not yet in the manifest and registers them (inferring title/type/date/entry the same way `migrate-legacy` does), atomically.

This means a session that gets killed mid-way still gets its partially-created folder registered — strictly better than the old behavior, where skipping the manifest-append step made the creation invisible forever. **Do not add a manifest-editing instruction back into `PROMPT.md`.** If the sync heuristic ever needs to change, change it in `corner_json.py`'s `cmd_sync_manifest`/`infer_type`, not by asking Claude to do it inline again.

---

## corner:update — complete plugin replacement

After `claude plugin update`, the old version directory may still exist in `~/.claude/plugins/cache/claude-corner/corner/`. All of this lives in one script, `.claude/commands/scripts/update.sh` — `update.md` is just a one-line wrapper around it plus the final summary. Running `claude plugin update` *inside* the script doesn't hide anything from Claude: the Bash tool call still captures its full stdout/stderr either way. The script must, in order:
1. Record `OLD_PLUGIN_ROOT`/`OLD_VERSION` before the update (via `corner_find_newest_plugin_dir`/`corner_plugin_version`)
2. Run `claude plugin update corner@claude-corner`, checking its exit code and aborting via `corner_die` before touching anything else if it fails
3. Find `NEW_PLUGIN_ROOT` (`corner_find_newest_plugin_dir` — dies loudly if it can't find one, since at this point one must exist)
4. If they differ: `rm -rf "$OLD_PLUGIN_ROOT"` — ensures no stale files remain
5. Print exactly one final line: `OLD_VERSION=x NEW_VERSION=y`

---

## corner:uninstall — total removal

Split across two scripts: `uninstall-check.sh` (read-only state dump, feeds the `AskUserQuestion` in `uninstall.md`) and `uninstall-purge.sh [--delete-corner-dir]` (does the actual removal). Each removal step in `uninstall-purge.sh` is isolated — one failing doesn't abort the rest; the script exits `3` with one `ERROR: <step> — <reason>` line per failure instead of stopping halfway.

Uninstall removes everything:
- Stop hook entry from `~/.claude/settings.json`
- All state files: `.corner-count`, `.corner-lock`, `.corner-done`, `.corner-interval`, `.corner-version-check`, `.corner-skip`
- Confinement settings: `~/claude-corner/.claude/settings.json`
- Plugin cache: `~/.claude/plugins/cache/claude-corner/` (entire directory)
- Optionally: `~/claude-corner/` and all user creations (ask first)

After uninstall, no corner-related files should remain in `~/.claude/`.

---

## Version bump workflow

1. Edit `.claude-plugin/plugin.json` — bump `version`
2. Edit `.claude-plugin/marketplace.json` — bump `metadata.version`
3. Commit and push to main
4. Run `/corner:update` in Claude Code to deploy the new version locally
