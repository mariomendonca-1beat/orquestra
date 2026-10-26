---
name: demandas-prs
description: Status dos PRs das demandas do orquestrador — por demanda não concluída, cada PR (STG/PRD, por repo) com merge (quando, por quem), conflito, último evento do flow (validado, deploy_hml, deploy_prod…), alertas (merjado sem deploy, ordem quebrada, PRD sem validado) e o próximo passo, mais o que mudou desde a última consulta. Use quando o usuário disser "me atualiza dos PRs", "teve merge?", "como estão os PRs das demandas?", "status das demandas", "o que falta para fechar X?". Não confundir com my-open-prs (PRs abertos do autor, sem demandas nem eventos de ciclo).
argument-hint: "[slug] [--todas]"
---

# PRs das demandas

Rode e mostre a saída **como sai** (tabelas e linhas de alerta intactas):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/orq" prs [slug] [--todas]
```

- Sem argumento: todas as demandas com arquivo `prs` e fase ≠ `concluida`. Com `slug`, só ela
  (em qualquer fase). `--todas` inclui as concluídas. `--json` devolve a análise crua.
- Só lê: uma chamada `gh api graphql` por repo, a topologia do flow no checkout local de cada
  repo e `demandas/*/prs`. Não precisa de herdr. Grava só `demandas/.prs-ultimo.json`, que
  alimenta a linha **Desde …** da próxima execução.

Depois das tabelas, 1–3 linhas suas: o que pede ação do usuário agora (alertas ⚠ primeiro,
depois os prontos para merge) e quais demandas podem ser fechadas (`orq fechar <slug>`, só
quando o usuário pedir). Não reformate as tabelas nem invente passos: o "Próximo" é heurística;
para o passo canônico de uma demanda, `/jaguar-plus:flow` na branch dela.

## Se algo falhar

- `gh` sem login: peça `! gh auth login`.
- Linha "⚠ <repo>: GitHub não respondeu": o resto do relatório vale; rode de novo em instantes.
- "referências sem URL ignoradas": o `prs` da demanda cita PRs só por número; eles não entram.
  Regrave os links com `orq estado <slug> pr-aberto "<links>"` se precisarem entrar.
