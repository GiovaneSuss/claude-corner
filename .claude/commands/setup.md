---
command: setup
description: Activate corner — creates ~/claude-corner/, registers the hook, and sets up path confinement
aliases:
  - install
allowed-tools: Bash, Read, Write
---

# Corner Setup

**Your first output line MUST be:** `🏠 Corner Setup`

Activate the corner plugin for this user. This registers a `Stop` hook so the corner fires automatically after every N responses.

## Step 1 — Scaffold the corner

```bash
bash "${CLAUDE_PLUGIN_ROOT}/.claude/commands/scripts/setup-scaffold.sh"
```

Se a saída tiver `ERROR:` ou o comando sair com código diferente de 0, repasse ao usuário e pare aqui.

## Step 2 — Ask for trigger interval

Use AskUserQuestion to ask:

- **Question**: "De quantas em quantas mensagens o corner deve ativar?"
- **Header**: "Intervalo"
- **Options**:
  - "3 mensagens" — frequente, description: "O corner ativa a cada 3 respostas"
  - "5 mensagens (recomendado)" — padrão, description: "Equilíbrio entre frequência e foco"
  - "10 mensagens" — moderado, description: "Menos interrupções, sessões mais espaçadas"
  - "20 mensagens" — raro, description: "Quase em segundo plano"

## Step 3 — Finish setup

Pass the chosen number (3, 5, 10, or 20 — or whatever the user typed in "Other") to the script. It validates the value itself (falls back to 5 if invalid):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/.claude/commands/scripts/setup-finish.sh" --interval INTERVALO_ESCOLHIDO
```

Se a saída tiver `ERROR:` ou o comando sair com código diferente de 0, repasse ao usuário.

## Step 4 — Show summary

```
🏠 Corner Setup — Concluído!

  Pasta:      ~/claude-corner/
  Frontend:   ~/claude-corner/index.html  (abre com /corner:view)
  Páginas:    ~/claude-corner/pages/      (Claude cria HTMLs aqui)
  Confinado:  só lê/escreve dentro de ~/claude-corner/
  Hook:       ativo — dispara a cada N mensagens (N = intervalo escolhido)
  Timeout:    5 minutos por sessão
  Prompt:     ~/claude-corner/PROMPT.md (editável)

Comandos disponíveis:
  /corner:now       → ativa o corner agora manualmente
  /corner:view      → abre o frontend no browser
  /corner:status    → vê o que foi criado no corner
  /corner:uninstall → desativa e remove tudo
```

Mencione que o usuário pode editar `~/claude-corner/PROMPT.md` para customizar o que o Claude faz no tempo livre.
