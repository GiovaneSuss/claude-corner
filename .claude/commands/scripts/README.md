# .claude/commands/scripts/ — script reference

Every slash command's mechanical work lives here, not in the `.md` files. Each `.md` wrapper is one Bash call plus whatever genuinely needs Claude's judgment (an `AskUserQuestion`, reading and describing a file). See `CLAUDE.md` at the repo root for why this split exists.

## Conventions

- **Exit codes:** `0` success · `1` expected failure (e.g. lock busy) · `2` environment/precondition failure · `3` partial failure (only `uninstall-purge.sh` uses this — some steps succeeded, some didn't).
- **Errors:** always on stderr, formatted `ERROR: <message>` (via `corner_die` in `hooks/lib.sh`). A `.md` wrapper that sees this — or a non-zero exit — must relay it to the user, never assume success.
- **Silence:** scripts print nothing on success unless the output IS the point of the command (`status.sh`, `uninstall-check.sh`, `update.sh`'s final version line, `setup-scaffold.sh`'s legacy-migration summary when it actually migrates something).
- **Sourcing `lib.sh`:** every script resolves its own directory via `realpath "$0"`, sources `$SCRIPT_DIR/../../../hooks/lib.sh` (or `$SCRIPT_DIR/lib.sh` for scripts inside `hooks/`), then calls `corner_resolve_plugin_root <fallback>` if it needs `PLUGIN_ROOT` (i.e. if it touches `templates/`). `<fallback>` is the plugin root computed relative to that script's own location — used only if `$CLAUDE_PLUGIN_ROOT` isn't set. Scripts that don't touch `templates/` (`status.sh`, `uninstall-check.sh`, `uninstall-purge.sh`) skip this and just source `lib.sh` for its constants/functions.
- **No blind `set -e`.** Some failures are tolerated on purpose (e.g. `rmdir` on a non-empty directory). Instead, anything that must succeed is followed by `|| corner_die "..."`.

## corner_json.py — the only JSON mutator

Every `.json` file the plugin writes goes through this CLI. It never truncates a file in place — every write is `.tmp` + `os.replace()`, so a crash mid-write can't corrupt something that used to parse. A missing file where that's fine (e.g. `settings.json` before any setup ever ran) is treated as an empty default, not an error; invalid JSON in a file that must exist is a hard error via `ERROR:` on stderr.

| Subcommand | Args | Used by |
|---|---|---|
| `migrate-legacy <corner_dir>` | | `setup-scaffold.sh` — moves pre-`pages/` root files into `pages/{slug}/`, registers them |
| `sync-manifest <corner_dir>` | | `corner_launch_session` (`hooks/lib.sh`) — registers any `pages/*` folder the free-time session created that isn't in the manifest yet |
| `list-manifest <manifest_path>` | | `status.sh` — read-only, prints `date [type] title` per entry |
| `write-confinement <corner_dir>` | | `setup-scaffold.sh` — writes `<corner_dir>/.claude/settings.json` (Read/Write/Edit allow-list scoped to the corner folder) |
| `register-hook <settings_path> <hook_cmd>` | | `setup-finish.sh` — adds/replaces the `Stop` hook entry |
| `remove-hook <settings_path>` | | `uninstall-purge.sh` — removes any `corner-trigger.sh` `Stop` hook entry |
| `update-hook-path <settings_path> <new_hook>` | | `update.sh` — repoints the hook at the newly-updated plugin path |
| `remove-plugin-registry <settings_path>` | | `uninstall-purge.sh` — pops `corner@claude-corner`/`claude-corner` from `enabledPlugins`/`extraKnownMarketplaces` |
| `remove-installed-plugin <path>` | | `uninstall-purge.sh` — pops the entry from `installed_plugins.json` |
| `remove-known-marketplace <path>` | | `uninstall-purge.sh` — pops the entry from `known_marketplaces.json` |

## Scripts

- **`now.sh`** — Activates the corner immediately. Sentinel, `corner_lock_check_and_clear` (exit 1 with `ERROR:` if busy), `corner_scaffold_minimal`, `corner_launch_session`. Runs standalone: `bash now.sh` with or without `CLAUDE_PLUGIN_ROOT` set.
- **`setup-scaffold.sh`** — Creates `~/claude-corner/`, copies/updates templates, migrates legacy files, writes the confinement `settings.json`, writes `.corner-env`. Silent except for a migration summary if it found legacy files.
- **`setup-finish.sh --interval N`** — Validates `N` (falls back to 5 if not a positive integer), saves it, registers the `Stop` hook, resets `.corner-count`.
- **`uninstall-check.sh`** — Read-only state dump (`corner_dir=`, `settings=`, `state_files=`, `corner_contents=`). Always visible — it's what the following `AskUserQuestion` is based on.
- **`uninstall-purge.sh [--delete-corner-dir]`** — Removes hook, state files, confinement settings, plugin cache, registry entries, marketplace clone, legacy hooks dir; deletes `~/claude-corner/` only if the flag is passed. Isolated failures, exit `3` on any.
- **`update.sh`** — Runs `claude plugin update corner@claude-corner` (checked, aborts loudly on failure), removes the old version directory, repoints the hook, refreshes `index.html`/assets/`server.py`/`sandbox.py` (backs up the old `index.html`), refreshes the version-check cache. Prints one line: `OLD_VERSION=x NEW_VERSION=y`.
- **`status.sh`** — Prints running state, prompt count, and the manifest listing. Uses `corner_lock_is_active` (pure read — a status check must never clear a lock as a side effect).
- **`view.sh`** — Ensures `pages/manifest.json` exists, starts `server.py` if port 8765 is free, opens the browser using the cached `BROWSER_OPEN_CMD` (self-heals if that command no longer exists on this system). Prints `URL=...` and `OPENED=yes/no`.

## `.corner-env` cache

Written by `setup-scaffold.sh` at `~/claude-corner/.corner-env` (KEY=VALUE, sourceable):

```
CACHE_VERSION=1
IS_WSL=yes
BROWSER_OPEN_CMD=wslview
```

`view.sh` loads it via `corner_load_env_cache` instead of re-probing `wslview`/`xdg-open`/`explorer.exe` on every call. If the cached command no longer exists, it re-detects once and rewrites the cache — it never gets stuck on a stale value.

## Running scripts outside Claude Code

Every script here works from a plain shell, with or without `CLAUDE_PLUGIN_ROOT` set (it falls back to a path computed relative to its own location, then validates it looks like the plugin repo):

```bash
bash .claude/commands/scripts/now.sh
CLAUDE_PLUGIN_ROOT=/path/to/claude-corner bash .claude/commands/scripts/status.sh
```

## Adding a new command

1. Put every mechanical/deterministic step in a new script here; source `hooks/lib.sh` for constants and shared functions.
2. Keep only what needs Claude's judgment (`AskUserQuestion`, reading/describing a file) in the `.md` wrapper.
3. Follow the exit-code and error-format conventions above — don't invent a new scheme.
4. If the script needs a new kind of JSON mutation, add a subcommand to `corner_json.py` rather than embedding a new `python3 -c` one-liner.
5. Document the new script/subcommand in this file.
