# Orquestrador de agentes Claude Code via herdr — Design

Data: 2026-10-09
Status: aprovado; implementado em 0.1.0 (plugin local)

## 1. Objetivo

Uma sessão Claude Code rodando em `jaguar/` vira um **orquestrador**: conversa com o
usuário sobre demandas, despacha cada demanda para outra sessão Claude Code (o
**líder**) e apenas espera e coordena. Demandas multi-repo são quebradas pelo líder
em sessões **dev**, uma por repo. Toda sessão é uma janela real do Claude Code em uma
pane do herdr — não subagents (subagents continuam livres *dentro* de cada sessão).

### Critérios de sucesso

- O usuário toca 2 a 4 demandas em paralelo conversando só com o orquestrador, saindo
  dele apenas quando quiser discutir um spec a fundo.
- Nenhuma demanda passa para implementação sem o spec aprovado pelo usuário.
- Após a aprovação, a demanda chega sozinha até PR(s) aberto(s) com `pr-self-review`,
  usando as skills do plugin `jaguar-plus`.
- Em demandas multi-repo, os PRs dos repos são coerentes entre si (mesmo contrato).
- Fechar o orquestrador, ou um agente morrer, não perde a demanda: tudo é retomável a
  partir de arquivos.

### Fora de escopo (por ora)

- Hooks do Claude Code para sinalização (abordagem C) — só se a detecção do herdr se
  mostrar insuficiente.
- Merge, promoção e tratamento de review (`pr-answer`) — continuam manuais / via flow.
- Execução remota ou em outras máquinas.

## 2. Papéis

| Papel | Onde roda | Faz | Não faz |
|---|---|---|---|
| **Orquestrador** | sessão do usuário, cwd `jaguar/` | conversa, cria demandas, apresenta gates, repassa decisões, acompanha estado | escrever código; decidir permissões ou aprovar specs sozinho |
| **Líder** | workspace herdr da demanda, cwd `jaguar/` | investiga os repos, escreve spec/contrato, implementa demandas de um repo, cria e coordena devs, check de integração final | sair do escopo aprovado; começar implementação antes de `aprovado` |
| **Dev** | pane no workspace da demanda, cwd = worktree do repo | implementa um repo conforme o contrato, verifica, abre PR(s), `pr-self-review` | falar com outro dev; mudar o contrato |

Regra de uso dos devs: **demanda de um repo só → o líder faz sozinho, sem devs.**
Demanda multi-repo → um dev por repo tocado.

Comunicação em estrela: usuário ⇄ orquestrador ⇄ líder ⇄ devs. Dev nunca fala com dev.

## 3. Componentes e arquivos

`.orquestra/` é um **plugin Claude Code local** com o mesmo layout do `jaguar-plus`
(`skills/`, `scripts/`), para que a migração futura para o `jaguar-plus` seja uma cópia.
Não é repositório git. Durante a validação, o orquestrador é aberto com
`claude --plugin-dir ~/Desktop/dev/jaguar/.orquestra` e invocado com
`/orquestra:orquestrador`. Só o orquestrador carrega o plugin; líder e devs recebem o
caminho absoluto do `orq` nos templates.

**Código e estado são separados.** O estado das demandas nunca mora dentro do plugin
(o cache de plugins é sobrescrito a cada versão). O `orq` acha a raiz (`ORQ_RAIZ`, ou
subindo de `$PWD` até uma pasta com `.orquestra/`) e guarda o estado em
`ORQ_ESTADO` (padrão `<raiz>/.orquestra/demandas`).

```
jaguar/
├── .orquestra/                        ← plugin local + estado
│   ├── .claude-plugin/plugin.json
│   ├── skills/orquestrador/SKILL.md   ← /orquestra:orquestrador
│   ├── scripts/orq                    ← script único de mecânica (bash 3.2)
│   ├── prompts/
│   │   ├── lider.md                   ← template do primeiro prompt do líder
│   │   └── dev.md                     ← template do primeiro prompt do dev
│   ├── tests/                         ← run.sh + herdr-stub
│   ├── docs/specs/                    ← este documento
│   └── demandas/<slug>/
│       ├── brief.md                   ← a demanda + feedbacks de gate anexados
│       ├── spec.md                    ← escrito pelo líder; objeto do gate
│       ├── contrato.md                ← só multi-repo; versionado no topo (v1, v2…)
│       ├── estado                     ← fase atual (uma palavra) + links de PR
│       ├── agentes                    ← "nome pane workspace papel repo worktree" (gerido pelo orq)
│       ├── historico                  ← log de transições
│       ├── prs                        ← links, gravados ao entrar em pr-aberto
│       └── <repo>.md                  ← canal dev → líder
└── <repo>-wt-<slug>/                  ← worktrees criadas pelo orq (convenção existente)
```

### 3.1 Skill `orquestrador` (`skills/orquestrador/SKILL.md`)

Prompt que transforma a sessão em orquestrador. Conteúdo:

- Papel e proibições (seção 2).
- Ao iniciar: verifica `HERDR_ENV=1`, roda `orq status`, resume demandas em voo e
  lança `orq esperar` em background.
- Como criar demanda: conversa até ter slug + descrição, então `orq nova`.
- Como apresentar um gate (seção 5.2).
- Como tratar `blocked` (seção 6.1).
- Loop: sempre que `orq esperar` termina, reporta o evento e relança.

### 3.2 `orq` (`.orquestra/scripts/orq`)

Único ponto que fala com `herdr` e `git`. Agentes nunca chamam `herdr` diretamente.
Toda saída é texto curto legível por LLM; erros saem com código ≠ 0 e mensagem
explicando o motivo e o próximo passo.

| Comando | Quem usa | Efeito |
|---|---|---|
| `orq nova <slug> <arquivo-brief>` | orquestrador | cria `demandas/<slug>/`, workspace herdr `<slug>`, sobe o líder `lider-<slug>` com `lider.md` preenchido; fase `nova` |
| `orq estado <slug> <fase> [nota]` | líder, orquestrador | muda a fase validando a transição (seção 4) |
| `orq dev <slug> <repo> <branch>` | líder | **exige fase `implementando`**; cria `<repo>-wt-<slug>` via `git worktree add` na branch existente, faz split de pane no workspace da demanda, sobe `dev-<slug>-<repo>` com `dev.md` preenchido |
| `orq falar <agente> "<msg>"` | orquestrador, líder | `herdr agent prompt`; em timeout, não reenvia — imprime as últimas linhas da pane |
| `orq ler <agente> [linhas]` | orquestrador, líder | `herdr agent read --source recent-unwrapped` |
| `orq teclas <agente> <tecla>…` | orquestrador | `herdr agent send-keys` (resposta a diálogo de permissão, sempre após decisão do usuário) |
| `orq status [slug]` | todos | tabela: demanda, fase, agentes, estado herdr de cada um (`working/idle/blocked/done/morto`) |
| `orq esperar [slug]` | orquestrador (global), líder (só sua demanda) | bloqueia até algo relevante mudar vs. último snapshot; imprime o que mudou e sai |
| `orq reviver <slug> [repo]` | orquestrador | sobe nova sessão no lugar de um agente morto, com template + "retome lendo `demandas/<slug>/`" |
| `orq fechar <slug>` | orquestrador, após o usuário pedir | fecha panes/workspace da demanda; remove worktrees cujo branch não tem mudanças locais pendentes; fase `concluida` |

Detalhes de mecânica:

- Agentes sobem com `herdr agent start <nome> --kind claude --pane <id> -- --permission-mode auto`.
- O papel do chamador vem de `ORQ_PAPEL` (`lider`/`dev`), injetado pelo `orq` no env do
  workspace/pane ao criá-lo; sem ele, o papel é `orquestrador`. É isso que permite ao
  `orq estado` barrar `aprovado` vindo do líder e ao `orq dev` barrar dev criando dev.
- Nomes: `lider-<slug>` e `dev-<slug>-<apelido>`, onde o apelido tira o prefixo
  `jaguar-plus-`/`jaguar-` do repo (`jaguar-plus` → `plus`). Slug até 18 caracteres.
- O primeiro prompt é o template preenchido; templates longos são escritos em
  `demandas/<slug>/` e o prompt aponta para o arquivo, evitando colar texto grande.
- `orq esperar` faz polling (intervalo ~10s) de `estado` + `herdr agent list`, compara
  com `demandas/.snapshot-<escopo>` e sai na primeira diferença relevante:
  - fase mudou para `spec-pronto`, `pr-aberto` ou outra;
  - agente ficou `blocked`;
  - agente ficou `idle`/`done` com a demanda em `implementando` (provável dúvida);
  - agente sumiu (`morto`).
- O orquestrador roda `orq esperar` com `run_in_background`, então segue conversando
  com o usuário enquanto espera e é reacordado quando o processo termina. O líder roda
  `orq esperar <slug> --max 540` em primeiro plano (cabe no limite do Bash) e repete.
- Escopo global (orquestrador) acorda com: mudança de fase, agente `blocked`, agente
  `morto`, líder `idle`. Escopo da demanda (líder) acorda com: dev `idle` ou `morto`.
  `done` é tratado como `idle`. Agentes que aparecem pela primeira vez viram base, sem evento.
- Nomes de agente seguem `[a-z][a-z0-9_-]{0,31}` (restrição do herdr): slugs são
  normalizados e truncados pelo `orq`.

### 3.3 Templates `lider.md` e `dev.md`

Preenchidos pelo `orq` (slug, caminhos, repos, branch). Contêm o papel, as proibições,
o protocolo de arquivos e quais skills do `jaguar-plus` usar em cada fase (seção 5).

## 4. Ciclo de vida (`estado`)

```
nova ─► investigando ─► spec-pronto ══GATE══► aprovado ─► implementando ─► pr-aberto ─► concluida
              ▲               │
              └── ajustes ────┘
```

| De → Para | Quem | Validação no `orq` |
|---|---|---|
| `nova → investigando` | líder | — |
| `investigando → spec-pronto` | líder | `spec.md` existe; se multi-repo, `contrato.md` existe |
| `spec-pronto → aprovado` | **somente orquestrador** | — |
| `spec-pronto → investigando` | orquestrador | nota (feedback) obrigatória; é anexada ao `brief.md` |
| `aprovado → implementando` | líder | — |
| `implementando → spec-pronto` | líder | nota obrigatória (delta de escopo) |
| `implementando → pr-aberto` | líder | ao menos um link de PR na nota |
| `* → concluida` | orquestrador via `orq fechar` | — |

Qualquer outra transição é recusada. O líder é instruído a só usar `aprovado` quando
recebê-lo, mas a garantia real é do script: `orq dev` e `implementando` são
impossíveis sem passar por `aprovado`.

`blocked` não é fase: é o estado vivo do herdr, mostrado ao lado da fase no `orq status`.

## 5. Fluxo de uma demanda

### 5.1 Investigação

1. Usuário descreve a demanda; orquestrador escreve o brief e roda `orq nova`.
2. Líder lê o brief, consulta `jaguar-plus:ledger` (modo consult), explora os repos
   envolvidos, escreve `spec.md`:
   - objetivo e critérios de aceite;
   - **repos tocados e o que entra em cada PR** (fecha o escopo do gate);
   - abordagem por repo; riscos.
3. Multi-repo: escreve `contrato.md` v1 (endpoints, payloads/tipos, chaves i18n,
   componentes compartilhados, ordem de merge).
4. `orq estado <slug> spec-pronto` e para.

### 5.2 Gate (híbrido)

1. `orq esperar` acorda o orquestrador com "demanda X: spec-pronto".
2. Orquestrador lê `spec.md`/`contrato.md` e apresenta um resumo: objetivo, repos e
   PRs previstos, decisões e riscos relevantes.
3. Usuário responde:
   - **aprova** → `orq estado <slug> aprovado` + `orq falar lider-<slug> "aprovado"`;
   - **ajuste simples** → `orq estado <slug> investigando "<feedback>"` + aviso ao líder;
   - **discussão profunda** → orquestrador indica o workspace do líder; o usuário
     conversa direto lá e, ao final, aprova pelo orquestrador ou pede ao líder para
     voltar a `spec-pronto` com o spec revisado.

### 5.3 Implementação

- Líder marca `implementando`.
- **Um repo:** líder executa ele mesmo: `branch-open` → implementação → verificação →
  `pr-open` → `pr-self-review`.
- **Multi-repo:**
  1. Líder roda `jaguar-plus:branch-open` em cada repo (corta a branch sem trocar de
     branch, seguro no checkout principal).
  2. `orq dev <slug> <repo> <branch>` para cada repo.
  3. Cada dev, na sua worktree: implementa conforme `contrato.md`, verifica (build,
     lint, testes do projeto), commita, `jaguar-plus:pr-open` (incluindo o par
     homologação/produção quando o fluxo do repo exigir), `jaguar-plus:pr-self-review`,
     escreve `## Feito` com links no `<repo>.md` e para.
  4. Líder roda `orq esperar <slug>` em loop, lê os `<repo>.md`, responde dúvidas.
  5. Com todos os devs em `## Feito`: **check de integração** — confronta os diffs dos
     PRs com `contrato.md` (nomes de campo, rotas, tipos, chaves i18n). Divergência →
     `orq falar` ao dev responsável.
  6. `orq estado <slug> pr-aberto "<links>"`.
- Push e abertura de PR **não** pedem nova aprovação, desde que dentro do escopo do
  `spec.md` aprovado.

### 5.3.1 `pr-open` é comando de usuário

`jaguar-plus:pr-open` (como `promote`, `sync` e `qa`) tem `disable-model-invocation`:
nenhum agente consegue invocá-lo sozinho. Ele é disparado **como texto de usuário** na
sessão certa:

- multi-repo: o dev preenche `## Pronto para PR` e para; o líder confere contra o
  contrato e roda `orq falar dev-... "/jaguar-plus:pr-open"`;
- um repo: o líder deixa o shell na worktree, escreve `PRONTO PARA PR: <worktree>` e para;
  o orquestrador, acordado pelo líder `idle`, roda `orq falar lider-<slug> "/jaguar-plus:pr-open"`.

Isso está dentro do que o gate autorizou (seção 5.3), então não pede nova aprovação.

### 5.4 Protocolo `<repo>.md` (dev → líder)

```markdown
## Status
<uma linha: o que está fazendo>

## Pergunta
<vazio, ou a dúvida para o líder; ao escrever, o dev para e espera>

## Pronto para PR
<vazio, ou: o que fez, como verificou, versão do contrato seguida>

## Feito
<vazio, ou: branch, links de PR, resultado do self-review>
```

O dev nunca responde ao líder pelo terminal; o líder nunca infere conclusão só pelo
estado `idle` — ele lê o arquivo.

### 5.5 Mudança de contrato

Só o líder edita `contrato.md`, incrementando a versão no topo. Se a mudança cabe no
escopo aprovado: atualiza e avisa **cada dev afetado** via `orq falar`. Se não cabe:
`orq estado <slug> spec-pronto "<delta>"` e novo gate.

## 6. Falhas

### 6.1 Permissões

- Filhos rodam em `--permission-mode auto`.
- Agente `blocked`: orquestrador roda `orq ler`, mostra ao usuário o que está sendo
  pedido e **nunca decide sozinho**. Decisão do usuário → `orq teclas`; ou o usuário
  responde direto na pane.
- Se um dev ficar `blocked`, o líder também não responde: deixa para o orquestrador
  (que já foi acordado pelo mesmo evento).

### 6.2 Tabela de falhas

| Situação | Tratamento |
|---|---|
| Agente morto / pane fechada | `orq status` mostra `morto`; orquestrador propõe `orq reviver` ao usuário |
| Agente idle sem atualizar arquivo | coordenador faz `orq ler` e pergunta via `orq falar`; nunca assume conclusão |
| `orq falar` com timeout | não reenvia; imprime a pane para decisão |
| Branch/worktree já existe | `orq dev` recusa e explica; líder/usuário decide |
| Transição de fase inválida | `orq estado` recusa, mostrando transições válidas |
| Orquestrador fechado | `/orquestrador` novamente: `orq status` + retomada |
| Não está no herdr | `/orquestrador` e `orq` abortam com mensagem clara |
| Diálogo "trust this folder" ao subir dev | Toda worktree nova é raiz git nova e dispara o diálogo. Só no `orq dev` (worktree que o próprio `orq` acabou de criar) o `orq` responde "sim" sozinho; em qualquer outro caso é `blocked` e vai ao usuário |
| `orq` reescrito com agentes rodando | O script é só definições + `main "$@"; exit` na última linha, então execuções em andamento não leem o arquivo novo pela metade |

## 7. Testes

1. **Unitários do `orq`** (`.orquestra/tests/`, bash): `herdr` stub no `PATH` que grava
   chamadas e devolve JSON fixo; repos git temporários. Cobre: transições válidas e
   inválidas, recusa de `orq dev` fora de `implementando`, normalização de nomes,
   detecção de mudanças do `orq esperar`, `fechar` não removendo worktree com mudanças.
2. **Smoke ponta a ponta:** sessão herdr isolada (`herdr --session orq-test`), dois
   repos git de brinquedo no scratchpad, demanda trivial multi-repo até `spec-pronto`,
   aprovação, devs até commit local. Sem push, sem tocar repos reais.
   Executado em 2026-10-09: o ciclo nova → investigando → spec-pronto → gate →
   implementando → 2 devs → pergunta de dev → líder devolvendo a `spec-pronto` com delta
   funcionou com sessões reais. Revelou o diálogo de trust e o risco de reescrever o
   script em execução, ambos tratados (seção 6.2).
3. **Primeira demanda real:** uma demanda simples só de frontend, para validar o
   trecho de PR com as skills do plugin.

## 8. Decisões registradas

- Sessões reais via herdr, não subagents, para orquestrador/líder/dev: cada dev carrega
  `CLAUDE.md`/skills do seu repo, é visível e interativo.
- Workspace herdr por demanda (hábito existente do usuário); worktrees irmãs
  `<repo>-wt-<slug>` via `git worktree add` (não `herdr worktree create`, que abriria
  workspace próprio).
- Mecânica centralizada em script (abordagem B); hooks adiados.
- Plugin local com layout do `jaguar-plus`, estado fora do plugin, para migrar copiando.
- Arquivos são a memória e o canal de resposta; terminal só para comandos.
- Human gate no spec; daí até PR aberto é autônomo dentro do escopo aprovado.
