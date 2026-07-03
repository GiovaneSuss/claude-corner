---
command: now
description: Trigger a corner session immediately (2-min free time)
allowed-tools: Bash
---

# Corner Now

Ativa o tempo livre imediatamente, sem esperar o intervalo configurado.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/.claude/commands/scripts/now.sh"
```

Se a saída começar com `ERROR:` ou o comando sair com código diferente de 0, repasse a mensagem ao usuário — não assuma sucesso. Caso contrário, diga ao usuário que o corner foi ativado em background e que algo novo aparecerá em `~/claude-corner/` em breve.
