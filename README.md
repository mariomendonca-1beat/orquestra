# orquestra

Orquestrador de demandas para Claude Code: uma sessão conversa com você e coordena outras
sessões Claude Code (um **líder** por demanda e um **dev** por repo) em panes do
[herdr](https://herdr.dev), com um gate humano no spec e PRs abertos pelas skills do
plugin `jaguar-plus`.

## Requisitos

- herdr (rodar dentro de uma pane: `HERDR_ENV=1`), `jq`, `git`
- Claude Code com o plugin `jaguar-plus` instalado
- Uma pasta raiz com os repos lado a lado; o plugin fica em `<raiz>/.orquestra/`

## Uso

```sh
claude --plugin-dir <raiz>/.orquestra     # e então: /orquestra:orquestrador
```

Comandos da mecânica: `scripts/orq ajuda`. Demandas criadas antes dos rótulos atuais:
`scripts/orq rotular` reaplica os nomes na lista de agentes do herdr. Testes: `bash tests/run.sh`.
Design completo: `docs/specs/2026-10-09-orquestrador-design.md`.

O estado das demandas fica em `demandas/`, fora do git.
