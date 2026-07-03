#!/usr/bin/env python3
"""Single CLI for every JSON mutation the corner plugin needs.

Subcommands are documented in .claude/commands/scripts/README.md. Every write
is atomic (.tmp + os.replace) so a crash mid-write can never corrupt a file
that used to parse. A missing file where it doesn't matter (settings.json on
a clean install, installed_plugins.json before any plugin was ever installed)
is a no-op success, not a crash — only invalid JSON in a file that must exist
is a hard error.
"""
import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime

SYSTEM = {
    'index.html', 'PROMPT.md', 'assets', 'pages', '.claude', 'notebook.md',
    'server.py', 'sandbox.py', '.corner-env',
}

DISPLAY_EXTS = {
    'html', 'htm', 'md', 'markdown', 'txt', 'text', 'ascii', 'asc', 'log',
    'js', 'mjs', 'svg', 'json',
    'py', 'sh', 'bash', 'ts', 'rs', 'go', 'rb', 'cpp', 'c', 'lua', 'r',
}


def die(msg, code=2):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def load_json(path, default=None):
    if not os.path.exists(path):
        if default is not None:
            return default
        die(f"file not found: {path}")
    try:
        with open(path) as fh:
            return json.load(fh)
    except json.JSONDecodeError as e:
        die(f"invalid JSON in {path}: {e}")


def save_json_atomic(path, data):
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    tmp = f"{path}.tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)


def ext_of(filename):
    return filename.rsplit('.', 1)[-1].lower() if '.' in filename else ''


def infer_type(slug, ext):
    s = slug.lower()
    if ext == 'md':
        return 'diary' if re.match(r'^\d{4}-\d{2}-\d{2}', s) else 'writing'
    if ext == 'svg':
        return 'art'
    if ext == 'html':
        for kw in ['fractal', 'newton', 'mandelbrot', 'melody', 'rule', 'sorting', 'harmony']:
            if kw in s:
                return 'animation'
        for kw in ['automaton', 'reaction', 'diffusion', 'simulation', 'voronoi', 'truchet']:
            if kw in s:
                return 'simulation'
        for kw in ['game', 'interact', 'touch', 'click']:
            if kw in s:
                return 'interactive'
        return 'animation'
    if ext == 'py':
        for kw in ['fern', 'fractal', 'plant', 'voronoi', 'sphere', 'terrain', 'apophenia']:
            if kw in s:
                return 'art'
        for kw in ['automaton', 'maze', 'ant', 'lsystem', 'ulam', 'rule']:
            if kw in s:
                return 'simulation'
        return 'code'
    return 'other'


def entry_priority(fn):
    return {'html': 0, 'htm': 0, 'svg': 1, 'py': 2, 'js': 3, 'md': 4}.get(ext_of(fn), 5)


def get_group_key(filename):
    base = os.path.splitext(filename)[0]
    if base.endswith('-note'):
        base = base[:-5]
    return base


def make_slug(key):
    s = re.sub(r'^\d{4}-\d{2}-\d{2}-', '', key)
    s = re.sub(r'[^a-z0-9]+', '-', s.lower())
    return s.strip('-') or 'untitled'


# ---- migrate-legacy: pre-pages files sitting in the corner root ----------

def cmd_migrate_legacy(args):
    corner = args.corner_dir
    pages_dir = os.path.join(corner, 'pages')
    manifest_path = os.path.join(pages_dir, 'manifest.json')
    os.makedirs(pages_dir, exist_ok=True)
    manifest = load_json(manifest_path, default=[])

    root_files = sorted(
        f for f in os.listdir(corner)
        if f not in SYSTEM and not f.startswith('.')
        and os.path.isfile(os.path.join(corner, f))
    )
    if not root_files:
        return

    print(f'Encontrados {len(root_files)} arquivo(s) legado(s) para migrar:')
    for f in root_files:
        print(f'  {f}')
    print()

    existing_folders = {e['folder'] for e in manifest}
    groups = {}
    for f in root_files:
        groups.setdefault(get_group_key(f), []).append(f)

    migrated = 0
    for key, files in groups.items():
        folder = make_slug(key)
        orig = folder
        i = 2
        while folder in existing_folders:
            folder = f'{orig}-{i}'
            i += 1

        page_dir = os.path.join(pages_dir, folder)
        os.makedirs(page_dir, exist_ok=True)

        sorted_files = sorted(files, key=entry_priority)
        entry_file = sorted_files[0]
        entry_ext = ext_of(entry_file)

        display_files = []
        for fn in files:
            src = os.path.join(corner, fn)
            shutil.move(src, os.path.join(page_dir, fn))
            if ext_of(fn) in DISPLAY_EXTS:
                display_files.append(fn)

        date_m = re.match(r'^(\d{4}-\d{2}-\d{2})', files[0])
        if date_m:
            date = date_m.group(1)
        else:
            mtime = os.path.getmtime(os.path.join(page_dir, files[0]))
            date = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d')

        title_key = re.sub(r'^\d{4}-\d{2}-\d{2}-', '', key)
        title = title_key.replace('-', ' ').replace('_', ' ').title()

        manifest.append({
            'title': title,
            'type': infer_type(key, entry_ext),
            'date': date,
            'folder': folder,
            'entry': entry_file,
            'files': display_files,
        })
        existing_folders.add(folder)
        print(f'  ✓ {", ".join(files)} → pages/{folder}/')
        migrated += 1

    manifest.sort(key=lambda e: e.get('date', ''), reverse=True)
    save_json_atomic(manifest_path, manifest)
    print(f'\n✓ {migrated} criação(ões) migrada(s) para pages/ e manifest atualizado.')


# ---- sync-manifest: register folders Claude created but never listed -----

def cmd_sync_manifest(args):
    corner = args.corner_dir
    pages_dir = os.path.join(corner, 'pages')
    manifest_path = os.path.join(pages_dir, 'manifest.json')
    if not os.path.isdir(pages_dir):
        return

    manifest = load_json(manifest_path, default=[])
    existing_folders = {e['folder'] for e in manifest}

    new_folders = sorted(
        d for d in os.listdir(pages_dir)
        if os.path.isdir(os.path.join(pages_dir, d)) and d not in existing_folders
    )

    added = 0
    for folder in new_folders:
        page_dir = os.path.join(pages_dir, folder)
        files = sorted(
            f for f in os.listdir(page_dir)
            if os.path.isfile(os.path.join(page_dir, f))
        )
        if not files:
            continue

        display_files = [f for f in files if ext_of(f) in DISPLAY_EXTS]
        if not display_files:
            continue

        sorted_files = sorted(display_files, key=entry_priority)
        entry_file = sorted_files[0]
        entry_ext = ext_of(entry_file)

        mtimes = [os.path.getmtime(os.path.join(page_dir, f)) for f in files]
        date = datetime.fromtimestamp(min(mtimes)).strftime('%Y-%m-%d')
        title = folder.replace('-', ' ').replace('_', ' ').title()

        manifest.append({
            'title': title,
            'type': infer_type(folder, entry_ext),
            'date': date,
            'folder': folder,
            'entry': entry_file,
            'files': display_files,
        })
        existing_folders.add(folder)
        added += 1

    if added:
        manifest.sort(key=lambda e: e.get('date', ''), reverse=True)
        save_json_atomic(manifest_path, manifest)
        print(f'✓ {added} nova(s) pasta(s) registrada(s) no manifest.')


# ---- list-manifest: read-only, used by status.sh --------------------------

def cmd_list_manifest(args):
    if not os.path.exists(args.manifest_path):
        print('(pasta não existe ainda — rode /corner:setup)')
        return
    data = load_json(args.manifest_path, default=[])
    if not data:
        print('(nenhuma criação ainda)')
        return
    for e in reversed(data):
        print(f"  {e.get('date', '')}  [{e.get('type', '?')}]  {e['title']}")


# ---- write-confinement -----------------------------------------------------

def cmd_write_confinement(args):
    corner = args.corner_dir
    data = {'permissions': {'allow': [
        f'Read({corner}/**)',
        f'Write({corner}/**)',
        f'Edit({corner}/**)',
    ]}}
    save_json_atomic(os.path.join(corner, '.claude', 'settings.json'), data)
    print('✓ settings.json de confinamento criado')


# ---- Stop hook registration / removal --------------------------------------

def cmd_register_hook(args):
    settings = load_json(args.settings_path, default={})
    hook = {'matcher': '', 'hooks': [{'type': 'command', 'command': args.hook_cmd, 'timeout': 5}]}
    hooks = settings.setdefault('hooks', {})
    entries = hooks.setdefault('Stop', [])
    entries[:] = [e for e in entries if args.hook_cmd not in json.dumps(e)]
    entries.append(hook)
    save_json_atomic(args.settings_path, settings)
    print('✓ Hook Stop registrado')


def cmd_remove_hook(args):
    settings = load_json(args.settings_path, default={})
    entries = settings.get('hooks', {}).get('Stop', [])
    before = len(entries)
    entries[:] = [e for e in entries if 'corner-trigger.sh' not in json.dumps(e)]
    removed = before - len(entries)
    if removed:
        save_json_atomic(args.settings_path, settings)
        print('Hook removido de ~/.claude/settings.json')
    else:
        print('— Hook não encontrado (ok)')


def cmd_update_hook_path(args):
    settings = load_json(args.settings_path, default={})
    updated = False
    for entry in settings.get('hooks', {}).get('Stop', []):
        for h in entry.get('hooks', []):
            if 'corner-trigger.sh' in h.get('command', '') and h['command'] != args.new_hook:
                h['command'] = args.new_hook
                updated = True
    if updated:
        save_json_atomic(args.settings_path, settings)
        print(f'hook atualizado para: {args.new_hook}')
    else:
        print('hook já estava atualizado')


# ---- uninstall registry cleanup -------------------------------------------

def cmd_remove_plugin_registry(args):
    settings = load_json(args.settings_path, default={})
    changed = False
    if settings.get('enabledPlugins', {}).pop('corner@claude-corner', None) is not None:
        changed = True
    if settings.get('extraKnownMarketplaces', {}).pop('claude-corner', None) is not None:
        changed = True
    if changed:
        save_json_atomic(args.settings_path, settings)
        print('✓ Registros de plugin/marketplace removidos de settings.json')
    else:
        print('— Nenhum registro em settings.json (ok)')


def cmd_remove_installed_plugin(args):
    data = load_json(args.path, default={})
    if data.get('plugins', {}).pop('corner@claude-corner', None) is not None:
        save_json_atomic(args.path, data)
        print('✓ Entrada removida de installed_plugins.json')
    else:
        print('— Nenhuma entrada em installed_plugins.json (ok)')


def cmd_remove_known_marketplace(args):
    data = load_json(args.path, default={})
    if data.pop('claude-corner', None) is not None:
        save_json_atomic(args.path, data)
        print('✓ Marketplace removido de known_marketplaces.json')
    else:
        print('— Nenhum marketplace registrado (ok)')


def main():
    parser = argparse.ArgumentParser(prog='corner_json.py')
    sub = parser.add_subparsers(dest='cmd', required=True)

    p = sub.add_parser('migrate-legacy')
    p.add_argument('corner_dir')
    p.set_defaults(func=cmd_migrate_legacy)

    p = sub.add_parser('sync-manifest')
    p.add_argument('corner_dir')
    p.set_defaults(func=cmd_sync_manifest)

    p = sub.add_parser('list-manifest')
    p.add_argument('manifest_path')
    p.set_defaults(func=cmd_list_manifest)

    p = sub.add_parser('write-confinement')
    p.add_argument('corner_dir')
    p.set_defaults(func=cmd_write_confinement)

    p = sub.add_parser('register-hook')
    p.add_argument('settings_path')
    p.add_argument('hook_cmd')
    p.set_defaults(func=cmd_register_hook)

    p = sub.add_parser('remove-hook')
    p.add_argument('settings_path')
    p.set_defaults(func=cmd_remove_hook)

    p = sub.add_parser('update-hook-path')
    p.add_argument('settings_path')
    p.add_argument('new_hook')
    p.set_defaults(func=cmd_update_hook_path)

    p = sub.add_parser('remove-plugin-registry')
    p.add_argument('settings_path')
    p.set_defaults(func=cmd_remove_plugin_registry)

    p = sub.add_parser('remove-installed-plugin')
    p.add_argument('path')
    p.set_defaults(func=cmd_remove_installed_plugin)

    p = sub.add_parser('remove-known-marketplace')
    p.add_argument('path')
    p.set_defaults(func=cmd_remove_known_marketplace)

    args = parser.parse_args()
    args.func(args)


if __name__ == '__main__':
    main()
