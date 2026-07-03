---
command: update
description: Update the corner plugin and refresh installed assets in ~/claude-corner/
allowed-tools: Bash
---

# Corner Update

**Your first output line MUST be:** `🏠 Corner Update`

Updates the plugin code and refreshes the viewer assets installed in `~/claude-corner/`, without touching the user's creations or `PROMPT.md`.

## Step 1 — Run the update

```bash
bash "${CLAUDE_PLUGIN_ROOT}/.claude/commands/scripts/update.sh"
```

Este único script já roda `claude plugin update corner@claude-corner`, então a saída completa desse comando aparece aqui — você a vê inteira, nada fica escondido.

Se a saída tiver `ERROR:` ou o comando sair com código diferente de 0, repasse a mensagem ao usuário e pare aqui. Caso contrário, a última linha é `OLD_VERSION=x NEW_VERSION=y`.

## Step 2 — Show summary

```
🏠 Corner Update — Concluído!

  Versão anterior: <OLD_VERSION>
  Versão nova:     <NEW_VERSION>
  hook path:       atualizado
  index.html:      atualizado (backup em index.html.bak)
  assets/:         atualizados
  server.py/sandbox.py: atualizados
  PROMPT.md:       mantido
  pages/:          mantido
```

Se um servidor antigo já estiver rodando na porta 8765 (iniciado antes deste update), ele continua sendo o `http.server` antigo até ser reiniciado — mencione ao usuário que basta rodar `/corner:view` depois de matar o processo antigo (`lsof -ti:8765 | xargs kill`) para o sandbox toggle aparecer funcional.

Se `OLD_VERSION` e `NEW_VERSION` forem iguais, mencione que o plugin já estava na última versão.
