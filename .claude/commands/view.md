---
command: view
description: Open Claude's Corner in the browser (starts local server if needed)
allowed-tools: Bash
---

# Corner View

Abre ~/claude-corner/ no browser com o frontend visual.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/.claude/commands/scripts/view.sh"
```

A saída traz `URL=...` e `OPENED=yes/no`. Diga ao usuário que o Corner está aberto nessa URL (mencione explicitamente se `OPENED=no`, incluindo a URL para abrir manualmente) e que o frontend atualiza automaticamente a cada 30 segundos conforme novas criações são adicionadas.
