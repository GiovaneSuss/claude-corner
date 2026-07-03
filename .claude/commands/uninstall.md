---
command: uninstall
description: Remove the corner plugin completely — hook, state files, plugin cache, and optionally ~/claude-corner/
aliases:
  - remove
allowed-tools: Bash, AskUserQuestion
---

# Corner Uninstall

**Your first output line MUST be:** `🏠 Corner Uninstall`

Remove everything installed by `/corner:setup` — hook, state files, plugin cache, and optionally `~/claude-corner/`.

## Step 1 — Check what exists

```bash
bash "${CLAUDE_PLUGIN_ROOT}/.claude/commands/scripts/uninstall-check.sh"
```

## Step 2 — Ask about the corner folder

Use AskUserQuestion to ask:

- **Question**: "O que fazer com ~/claude-corner/ e os arquivos criados pelo Claude lá?"
- **Options**:
  - "Manter a pasta e os arquivos" — only removes settings.json and state, keeps creations
  - "Apagar tudo (pasta + arquivos)" — full wipe

## Step 3 — Purge

```bash
bash "${CLAUDE_PLUGIN_ROOT}/.claude/commands/scripts/uninstall-purge.sh"
```

Se o usuário escolheu apagar tudo, passe a flag em vez disso:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/.claude/commands/scripts/uninstall-purge.sh" --delete-corner-dir
```

O script continua mesmo se um passo individual falhar. Se sair com código `3`, ele imprimiu uma ou mais linhas `ERROR: <passo> — <motivo>` em stderr — repasse cada uma ao usuário antes do resumo final.

Nota: se este comando estiver rodando a partir do próprio plugin corner, o runtime pode recriar o diretório de cache do plugin (marcado como `.orphaned_at`/`.in_use`) enquanto a sessão está ativa. Isso é esperado e se autolimpa no próximo restart do Claude Code.

## Step 4 — Show final summary

```
🏠 Corner Uninstall — Concluído!

  Arquivos de estado:        removidos
  Plugin cache:              removido de ~/.claude/plugins/cache/
  Registros de plugin:        removidos (settings.json, installed_plugins.json, known_marketplaces.json)
  Marketplace + hooks legado: removidos
  settings.json:              removido
  ~/claude-corner/:           [mantida / removida]
```

Preencha `[mantida / removida]` de acordo com a escolha do usuário no Step 2.
