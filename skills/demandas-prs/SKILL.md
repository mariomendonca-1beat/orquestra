---
name: demandas-prs
description: O quadro das demandas do orquestrador — uma linha por demanda em voo com Situação e Próximo passo / quem (Igor, Guilherme, CS, você), recados prontos por pessoa e as decisões pendentes do usuário, com estado e vez vindos da fila do /jaguar-plus:flow. Com slug ou --detalhe, as tabelas por PR (merge, conflito, eventos, alertas). Use quando o usuário disser "me atualiza das demandas", "como estão os PRs?", "teve merge?", "status das demandas", "o que falta para fechar X?", "o que eu mando pro Igor?". Não confundir com my-open-prs (PRs abertos do autor, sem demandas nem ciclo).
argument-hint: "[slug] [--detalhe] [--rapido] [--todas]"
---

# Quadro das demandas

Rode o comando da tabela, com **timeout de 600000 ms** no Bash (a fila do flow fria leva ~3 min), e
mostre a saída **como sai**: não reformate, não reordene, não resuma, não troque palavras.

| Chamada | Comando |
|---|---|
| `/demandas-prs` | `"${CLAUDE_PLUGIN_ROOT}/scripts/orq" prs --quadro` |
| `/demandas-prs --rapido` | `"${CLAUDE_PLUGIN_ROOT}/scripts/orq" prs --quadro --rapido` (fila em cache, mesmo velha; mostra a idade) |
| `/demandas-prs <slug>` | `"${CLAUDE_PLUGIN_ROOT}/scripts/orq" prs <slug>` (tabelas por PR daquela demanda) |
| `/demandas-prs --detalhe` | `"${CLAUDE_PLUGIN_ROOT}/scripts/orq" prs` (tabelas por PR de todas) |
| `--todas` | acrescente `--todas` (inclui concluídas) |

- Só lê: GitHub (`gh api graphql`), a fila do `/jaguar-plus:flow` (`flow-queue.mjs --resumo` do plugin
  instalado no escopo de usuário, no checkout de cada repo; cache de 15 min em `demandas/.fila/`) e os
  arquivos das demandas. Grava só caches em `demandas/`. Não precisa de herdr.
- Pessoas, nomes curtos dos repos, ordem de merge e TTL: `config/pessoas.json`. Contexto humano que não está
  no GitHub entra por `orq nota <slug> "<texto>"`.
- ⚠ só marca risco de quebrar produção; ℹ é sinal leve (STG fora de ordem é normal).

Depois da saída, no máximo **uma** linha sua, e só com o que o quadro não mostra (ex.: um agente
`blocked` que o orquestrador conhece). Para o passo canônico de uma demanda: `/jaguar-plus:flow` na branch dela.

## Se algo falhar

- `gh` sem login: peça `! gh auth login`.
- "ℹ fila do flow indisponível em <repo> (<motivo>)": o quadro saiu com a heurística do orq para aquele repo.
  Plugin ausente ou antigo: `claude plugin update jaguar-plus@onebeat` (o usuário roda). Timeout: rode de novo
  ou use `--rapido`.
- Linha "GitHub não respondeu": o resto vale; rode de novo em instantes.
