---
command: status
description: Show what Claude created in ~/claude-corner/
allowed-tools: Bash, Read
---

# Corner Status

Mostra o histórico do tempo livre do Claude.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/.claude/commands/scripts/status.sh"
```

Liste as criações encontradas e leia o conteúdo da mais recente para mostrar ao usuário o que o Claude criou no último tempo livre.

Se o corner estiver rodando agora, mencione isso também.
