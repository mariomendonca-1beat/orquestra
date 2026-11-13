#!/usr/bin/env bash
# Testes do orq com um herdr falso e repos git temporários.  Uso: bash tests/run.sh
set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
ORQ="$AQUI/../scripts/orq"
HOME_ORQ="$(cd "$AQUI/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export STUB_DIR="$T/stub" ORQ_HERDR="$AQUI/herdr-stub" ORQ_RAIZ="$T/raiz" ORQ_INTERVALO=1 ORQ_PAINEL=0
# nunca o plugin nem o GitHub de verdade: sem plugin instalado e sem poll do GitHub, salvo onde o teste liga
export ORQ_PLUGINS_JSON="$T/sem-plugin.json" ORQ_GITHUB_INTERVALO=0 ORQ_FILA_NODE="$AQUI/fila-stub"
unset ORQ_PAPEL ORQ_ESTADO
mkdir -p "$STUB_DIR" "$ORQ_RAIZ/.orquestra"
ESTADO="$ORQ_RAIZ/.orquestra/demandas"

falhas=0
ok()   { echo "  ✓ $1"; }
nok()  { echo "  ✗ $1"; falhas=$((falhas + 1)); }
deve_passar() { local d="$1"; shift; if out="$("$@" 2>&1)"; then ok "$d"; else nok "$d — $out"; fi; }
deve_falhar() { local d="$1" padrao="$2"; shift 2
  if out="$("$@" 2>&1)"; then nok "$d — passou e não devia"
  elif echo "$out" | grep -q "$padrao"; then ok "$d"
  else nok "$d — erro inesperado: $out"; fi; }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1 — esperado '$3', veio '$2'"; fi; }
status_stub() { # nome status
  sed -i '' -e "s/^$1 [a-z]* /$1 $2 /" "$STUB_DIR/agents" 2>/dev/null \
    || sed -i -e "s/^$1 [a-z]* /$1 $2 /" "$STUB_DIR/agents"; }

novo_repo() { # nome branch
  git init -q "$ORQ_RAIZ/$1"
  git -C "$ORQ_RAIZ/$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$ORQ_RAIZ/$1" branch "$2"
}

echo "brief da demanda" > "$T/brief.md"

echo "nova"
deve_falhar "slug inválido" "slug inválido" "$ORQ" nova "X_ruim" "$T/brief.md"
deve_passar "cria demanda" "$ORQ" nova pivot "$T/brief.md"
igual "fase inicial" "$(cat "$ESTADO/pivot/estado")" nova
grep -q "agent start lider-pivot --kind claude --pane w1:p1 .*--permission-mode auto" "$STUB_DIR/calls" \
  && ok "líder sobe em modo auto" || nok "líder sobe em modo auto"
grep -q "ORQ_PAPEL=lider" "$STUB_DIR/calls" && ok "workspace marca papel lider" || nok "papel lider"
grep -q "workspace create .*--label pivot --no-focus" "$STUB_DIR/calls" && ok "workspace rotulado só com o slug" || nok "workspace rotulado"
grep -q "workspace create .*--env DISABLE_AUTO_UPDATE=true" "$STUB_DIR/calls" && ok "workspace sem update do omz" || nok "omz env no workspace"
grep -q "pane report-metadata w1:p1 --source orq --agent claude --display-agent lider" "$STUB_DIR/calls" \
  && ok "líder exibido como lider na lista de agentes" || nok "display-agent do líder"
grep -q "Leia $HOME_ORQ/prompts/self-review.md" "$ESTADO/pivot/.prompt-lider.md" \
  && ok "líder aponta o self-review em subagent" || nok "self-review no prompt do líder"
[ -s "$HOME_ORQ/prompts/self-review.md" ] && ok "prompt do subagent de self-review existe" || nok "prompts/self-review.md"
grep -q "pane rename w1:p1 pivot - lider" "$STUB_DIR/calls" && ok "pane do líder rotulada" || nok "pane do líder rotulada"
grep -q "agent prompt lider-pivot Leia o arquivo $ESTADO/pivot/.prompt-lider.md" "$STUB_DIR/calls" \
  && ok "líder recebe o template" || nok "líder recebe o template"
grep -q "{{" "$ESTADO/pivot/.prompt-lider.md" && nok "template sem placeholders" || ok "template sem placeholders"
deve_falhar "demanda duplicada" "já existe" "$ORQ" nova pivot "$T/brief.md"

echo "estado e gate"
deve_falhar "pular para aprovado" "inválida" "$ORQ" estado pivot aprovado
deve_passar "nova -> investigando" env ORQ_PAPEL=lider "$ORQ" estado pivot investigando
deve_falhar "spec-pronto sem spec" "exige" env ORQ_PAPEL=lider "$ORQ" estado pivot spec-pronto
echo "# spec" > "$ESTADO/pivot/spec.md"
deve_passar "-> spec-pronto" env ORQ_PAPEL=lider "$ORQ" estado pivot spec-pronto
deve_falhar "líder não se aprova" "só o orquestrador" env ORQ_PAPEL=lider "$ORQ" estado pivot aprovado
deve_falhar "devolver sem feedback" "feedback" "$ORQ" estado pivot investigando
deve_passar "devolver com feedback" "$ORQ" estado pivot investigando "trocar a coluna X"
grep -q "trocar a coluna X" "$ESTADO/pivot/brief.md" && ok "feedback anexado ao brief" || nok "feedback no brief"
env ORQ_PAPEL=lider "$ORQ" estado pivot spec-pronto >/dev/null
deve_passar "orquestrador aprova" "$ORQ" estado pivot aprovado

echo "dev"
novo_repo jaguar-plus-frontend feat/pivot
deve_falhar "dev antes de implementando" "implementando" env ORQ_PAPEL=lider "$ORQ" dev pivot jaguar-plus-frontend feat/pivot
env ORQ_PAPEL=lider "$ORQ" estado pivot implementando >/dev/null
deve_falhar "dev não cria dev" "dev não cria" env ORQ_PAPEL=dev "$ORQ" dev pivot jaguar-plus-frontend feat/pivot
deve_falhar "branch inexistente" "branch-open" env ORQ_PAPEL=lider "$ORQ" dev pivot jaguar-plus-frontend nao-existe
deve_passar "cria dev" env ORQ_PAPEL=lider "$ORQ" dev pivot jaguar-plus-frontend feat/pivot
[ -d "$ORQ_RAIZ/jaguar-plus-frontend-wt-pivot" ] && ok "worktree criada" || nok "worktree criada"
igual "branch da worktree" "$(git -C "$ORQ_RAIZ/jaguar-plus-frontend-wt-pivot" branch --show-current)" feat/pivot
grep -q "agent start dev-pivot-frontend" "$STUB_DIR/calls" && ok "nome curto do dev" || nok "nome curto do dev"
grep -q "pane split --pane w1:p1 --direction right" "$STUB_DIR/calls" && ok "1º dev à direita do líder" || nok "1º dev à direita"
[ -f "$ESTADO/pivot/jaguar-plus-frontend.md" ] && ok "canal do dev criado" || nok "canal do dev"
grep -q "pane rename w1:p[0-9]* pivot - dev frontend" "$STUB_DIR/calls" && ok "pane do dev rotulada" || nok "pane do dev rotulada"
grep -q "pane report-metadata w1:p[0-9]* --source orq --agent claude --display-agent dev frontend" "$STUB_DIR/calls" \
  && ok "dev exibido com o próprio nome na lista de agentes" || nok "display-agent do dev"
grep -q "pane split .*--env ORQ_PAPEL=dev .*--env DISABLE_AUTO_UPDATE=true" "$STUB_DIR/calls" && ok "pane do dev sem update do omz" || nok "omz env no split"
P="$ESTADO/pivot/.prompt-dev-jaguar-plus-frontend.md"
grep -q "{{" "$P" && nok "prompt do dev sem placeholders" || ok "prompt do dev sem placeholders"
grep -q "Leia $HOME_ORQ/prompts/self-review.md e siga. worktree=$ORQ_RAIZ/jaguar-plus-frontend-wt-pivot" "$P" \
  && ok "dev despacha self-review em subagent" || nok "self-review no prompt do dev"
deve_falhar "dev duplicado" "já existe" env ORQ_PAPEL=lider "$ORQ" dev pivot jaguar-plus-frontend feat/pivot
novo_repo jaguar-plus feat/pivot
"$ORQ" dev pivot jaguar-plus feat/pivot >/dev/null 2>&1
grep -q "pane split --pane w1:p[0-9]* --direction down" "$STUB_DIR/calls" && ok "2º dev empilhado" || nok "2º dev empilhado"

novo_repo jaguar-plus-ui feat/pivot
out="$(STUB_TRUST=1 "$ORQ" dev pivot jaguar-plus-ui feat/pivot 2>&1)"
echo "$out" | grep -q "confiei na worktree nova" && ok "dev confia na worktree nova" || nok "trust dev: $out"
grep -q "agent send-keys dev-pivot-ui down enter" "$STUB_DIR/calls" && ok "responde o diálogo com down+enter" || nok "teclas trust"
rm -rf "$ORQ_RAIZ/.orquestra/demandas/trust"
STUB_TRUST=1 "$ORQ" nova trust "$T/brief.md" >/dev/null 2>&1 && nok "líder não confia sozinho" || ok "líder não confia sozinho"
sed -i '' '/^dev-pivot-ui \|^lider-trust /d' "$STUB_DIR/agents" 2>/dev/null; rm -rf "$ESTADO/trust"
grep -v '^dev-pivot-ui ' "$STUB_DIR/agents" | grep -v '^lider-trust ' > "$STUB_DIR/a2"; mv "$STUB_DIR/a2" "$STUB_DIR/agents"
awk '$1!="dev-pivot-ui"' "$ESTADO/pivot/agentes" > "$T/ag"; mv "$T/ag" "$ESTADO/pivot/agentes"

echo "esperar"
deve_falhar "--max sem eventos" "nada relevante" "$ORQ" esperar --max 1
"$ORQ" esperar > "$T/ev" 2>&1 & pid=$!
sleep 1; status_stub dev-pivot-frontend blocked
wait $pid; grep -q "dev-pivot-frontend dev blocked" "$T/ev" && ok "global acorda com blocked" || nok "global blocked: $(cat "$T/ev")"
status_stub dev-pivot-frontend working
"$ORQ" esperar --max 1 >/dev/null 2>&1   # rebaseline
"$ORQ" esperar pivot > "$T/ev2" 2>&1 & pid=$!
sleep 1; status_stub dev-pivot-plus idle
# idle já era o estado inicial do plus no stub; forçamos working -> idle
status_stub dev-pivot-plus working; sleep 2; status_stub dev-pivot-plus idle
wait $pid; grep -q "dev-pivot-plus dev idle" "$T/ev2" && ok "líder acorda com dev idle" || nok "líder dev idle: $(cat "$T/ev2")"
sed -i '' '/^dev-pivot-plus /d' "$STUB_DIR/agents" 2>/dev/null || sed -i '/^dev-pivot-plus /d' "$STUB_DIR/agents"
"$ORQ" esperar --max 5 > "$T/ev3" 2>&1
grep -q "dev-pivot-plus dev morto" "$T/ev3" && ok "agente sumido vira morto" || nok "morto: $(cat "$T/ev3")"
"$ORQ" status | grep -q "dev-pivot-plus.*morto" && ok "status mostra morto" || nok "status morto"

echo "reviver"
deve_falhar "não revive vivo" "está vivo" "$ORQ" reviver pivot jaguar-plus-frontend
deve_passar "revive dev morto" "$ORQ" reviver pivot jaguar-plus
grep -q "RETOMADA" "$ESTADO/pivot/.prompt-dev-jaguar-plus.md.retomada" && ok "prompt de retomada" || nok "retomada"

echo "falar"
deve_passar "falar com vivo" "$ORQ" falar lider-pivot "oi"
deve_falhar "falar com inexistente" "NÃO reenvie" "$ORQ" falar fantasma "oi"

echo "pr-aberto e fechar"
deve_falhar "pr-aberto sem link" "links" env ORQ_PAPEL=lider "$ORQ" estado pivot pr-aberto "feito"
deve_passar "pr-aberto com link" env ORQ_PAPEL=lider "$ORQ" estado pivot pr-aberto "https://github.com/x/y/pull/1"
deve_falhar "regravar links sem link" "links" env ORQ_PAPEL=lider "$ORQ" estado pivot pr-aberto "mudou"
deve_passar "regrava links em pr-aberto" env ORQ_PAPEL=lider "$ORQ" estado pivot pr-aberto "https://github.com/x/y/pull/2"
igual "prs regravado" "$(cat "$ESTADO/pivot/prs")" "https://github.com/x/y/pull/2"
grep -q "pr-aberto -> pr-aberto | https://github.com/x/y/pull/2" "$ESTADO/pivot/historico" && ok "histórico da regravação" || nok "histórico regravação"
out="$("$ORQ" status pivot 2>&1)"; echo "$out" | grep -q "pr-aberto — https://github.com/x/y/pull/2" && ok "status mostra links novos" || nok "status links novos: $out"

echo "rotular"
out="$("$ORQ" rotular pivot 2>&1)"
echo "$out" | grep -q "rótulos reaplicados a 3 agente" && ok "rotula os agentes vivos" || nok "rotular: $out"
grep -q "workspace rename w1 pivot" "$STUB_DIR/calls" && ok "renomeia o workspace para o slug" || nok "workspace rename"
grep -q "pane report-metadata .*--display-agent dev plus" "$STUB_DIR/calls" && ok "rotular dá nome ao dev plus" || nok "rotular dev plus"
deve_falhar "rotular demanda inexistente" "não existe" "$ORQ" rotular fantasma
echo sujo > "$ORQ_RAIZ/jaguar-plus-frontend-wt-pivot/arq"
out="$("$ORQ" fechar pivot 2>&1)"
echo "$out" | grep -q "mantida .*frontend-wt-pivot: tem mudanças" && ok "mantém worktree suja" || nok "worktree suja: $out"
echo "$out" | grep -q "mantida .*jaguar-plus-wt-pivot: branch sem upstream" && ok "mantém branch sem push" || nok "sem upstream: $out"
igual "fase final" "$(cat "$ESTADO/pivot/estado")" concluida
out="$("$ORQ" rotular 2>&1)"
echo "$out" | grep -q "a 0 agente" && ok "rotular ignora concluídas" || nok "rotular concluída: $out"

echo "subida protegida"
out="$(STUB_OMZ=1 "$ORQ" nova omz "$T/brief.md" 2>&1)"
echo "$out" | grep -q "respondi 'n' ao update do oh-my-zsh" && ok "destrava o prompt do omz e sobe" || nok "omz: $out"
grep -q "pane send-keys w[0-9]*:p1 n" "$STUB_DIR/calls" && grep -q "pane send-keys w[0-9]*:p1 ctrl+u" "$STUB_DIR/calls" \
  && ok "responde n e limpa a linha" || nok "teclas omz"
igual "duas tentativas de subida" "$(grep -c "agent start lider-omz" "$STUB_DIR/calls")" 2
grep -q "agent prompt lider-omz Leia o arquivo" "$STUB_DIR/calls" && ok "prompt entregue depois do omz" || nok "prompt pós-omz"
teclas_antes="$(grep -c "send-keys" "$STUB_DIR/calls")"
out="$(STUB_AUTOMODE=1 "$ORQ" nova am "$T/brief.md" 2>&1)" && nok "diálogo do auto mode devia falhar" || {
  echo "$out" | grep -q "setup do auto mode" && echo "$out" | grep -q "orq falar lider-am \"Leia o arquivo" \
    && ok "detecta o diálogo do auto mode e diz como seguir" || nok "auto mode: $out"; }
grep -q "agent prompt lider-am" "$STUB_DIR/calls" && nok "não entrega prompt com diálogo aberto" || ok "não entrega prompt com diálogo aberto"
igual "não responde o auto mode (nenhuma tecla enviada)" "$(grep -c "send-keys" "$STUB_DIR/calls")" "$teclas_antes"

echo "prs"
EP="$T/estado-prs"; FX="$T/fixtures"; mkdir -p "$EP" "$FX"
export GH_FIXTURES="$FX"
for r in jaguar-plus jaguar-beta outro unico; do jq -n -f "$AQUI/fixtures/prs.jq" | jq --arg r "$r" '.[$r]' > "$FX/$r.json"; done
mkdir -p "$ORQ_RAIZ/jaguar-plus/.claude/flow" "$ORQ_RAIZ/jaguar-beta/.claude/flow" "$ORQ_RAIZ/unico/.claude/flow"
echo '{"hml":null,"prod":"main","migracao_automatica":true,"migracao_paths":[]}' > "$ORQ_RAIZ/unico/.claude/flow/topology.json"
echo '{"hml":"staging","prod":"production","migracao_automatica":false,"migracao_paths":["*.sql"],
  "migracao_cmd":{"hml":"/deploy staging","prod":"/deploy production"}}' > "$ORQ_RAIZ/jaguar-plus/.claude/flow/topology.json"
echo '{"hml":"staging","prod":"master","migracao_automatica":true,"migracao_paths":[]}' > "$ORQ_RAIZ/jaguar-beta/.claude/flow/topology.json"
dem() { # slug fase linha-do-prs...
  local s="$1" f="$2"; shift 2; mkdir -p "$EP/$s"; echo "$f" > "$EP/$s/estado"; printf '%s\n' "$@" > "$EP/$s/prs"; }
B=https://github.com/onebeatco/jaguar-beta/pull; P=https://github.com/onebeatco/jaguar-plus/pull
dem d-conflito pr-aberto "$B/10 (HML)" "$B/11 (PROD)"
dem d-ordem pr-aberto "$P/20" "$P/21"
dem d-ordem2 pr-aberto "$P/22" "$P/23"
dem d-semstg pr-aberto "$P/24"
dem d-behind pr-aberto "$B/61"
dem d-sumido pr-aberto "$B/999" "$B/64" "$P/34"
dem d-semprd pr-aberto "$B/62" "$B/63 (PROD fechado)"
dem d-unico pr-aberto "https://github.com/onebeatco/unico/pull/1" "https://github.com/onebeatco/unico/pull/2"
dem d-deploy pr-aberto "$P/30" "$P/31"
dem d-semval pr-aberto "$B/40" "$B/41" "$B/42"
dem d-prod pr-aberto "$P/32" "$P/33"
dem d-pronto pr-aberto "$B/50" "$B/51"
dem d-unknown implementando "$B/60"
dem d-semtopo pr-aberto "https://github.com/onebeatco/outro/pull/70"
dem d-feita concluida "$B/80"
dem d-refs pr-aberto "$B/90 (HML, substitui #99)" "$B/91" "$B/91 (repetido)"
mkdir -p "$EP/d-semprs"; echo spec-pronto > "$EP/d-semprs/estado"
prs() { env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EP" ORQ_PRS_ESPERAS="0 0" ORQ_PRS_ESPERA_UNKNOWN=0 \
  ORQ_GH="$AQUI/gh-stub" "$ORQ" prs --sem-fila "$@"; }
rm -f "$STUB_DIR"/gh-*
out="$(prs 2>&1)" && ok "prs roda fora do herdr" || nok "prs fora do herdr: $out"
igual "uma chamada completa por repo" "$(grep -c completa "$STUB_DIR/gh-calls")" 4
igual "UNKNOWN re-consulta só os abertos UNKNOWN" "$(grep leve "$STUB_DIR/gh-calls" | sort -u | tr '\n' '|')" "jaguar-beta leve 51 60 |jaguar-beta leve 60 |"
tem() { echo "$out" | grep -qF -- "$2" && ok "$1" || nok "$1 — não achei: $2"; }
nao() { echo "$out" | grep -qF -- "$2" && nok "$1 — achei: $2" || ok "$1"; }
tem "conflito" "⚠ jaguar-beta#11: em conflito com \`master\`"
tem "passo do conflito" "→ Próximo: jaguar-beta: resolver o conflito de #11"
tem "ordem quebrada já remediada" "⚠ jaguar-plus#21: ordem quebrada: PRD merjado antes de qualquer STG do repo (E-011); o STG entrou depois (20/10"
tem "remediada não bloqueia o passo" "pode fechar: \`orq fechar d-ordem\`"
tem "PRD merjado sem STG listado" "⚠ jaguar-plus#24: PRD merjado e nenhum STG do repo listado na demanda: ordem não verificada"
tem "STG aprovado mas BEHIND tem passo" "→ Próximo: jaguar-beta: STG #61 aprovado: merjar"
tem "STG merjado sem PRD vivo não é 'pode fechar'" "→ Próximo: jaguar-beta: validar em HML e registrar \`flow validado\`; nenhum PRD vivo listado na demanda"
nao "ambiente único sem alerta de STG" "unico#1: PRD merjado e nenhum STG"
tem "ambiente único: PRD aberto aguarda review" "→ Próximo: unico: PRD #2 aguarda review/merge"
tem "PR inexistente não derruba o relatório" "⚠ jaguar-beta#999: PR não encontrado no GitHub"
tem "PR com mais de 100 arquivos avisa onde a migração é manual" "ℹ jaguar-plus#34: mais de 100 arquivos"
nao "sem aviso de arquivos onde a migração é automática" "jaguar-beta#64: mais de 100"
tem "ordem quebrada pendente" "→ Próximo: jaguar-plus: ordem quebrada em #22: merjar o STG #23 e conferir o ambiente de HML (E-011)"
tem "sql merjado com deploy_hml anterior ao merge alerta" "⚠ jaguar-plus#30: merjado sem \`deploy_hml\`: migração não registrada como aplicada (\`/deploy staging\`)"
tem "passo do deploy" "→ Próximo: jaguar-plus: aplicar a migração: /deploy staging (#30)"
nao "deploy_hml posterior ao merge cala o alerta" "jaguar-plus#20: merjado sem"
tem "sql merjado em PRD com deploy_prod anterior ao merge alerta" "⚠ jaguar-plus#33: merjado sem \`deploy_prod\`: migração não registrada como aplicada (\`/deploy production\`)"
tem "base fora da topologia" "⚠ jaguar-beta#42: base \`develop\` não é a de HML nem a de PROD"
tem "PRD sem validado (antigo e de bot não contam)" "⚠ jaguar-beta#41: PRD aberto sem \`validado\`"
tem "passo validar" "validar em HML e registrar \`flow validado\`; depois merjar o PRD #41"
tem "UNKNOWN resolvido no retry" "| jaguar-beta | [#51](https://github.com/o/r/pull/51) | PRD | 🟡 aberto | BLOCKED (falta aprovação) |"
tem "pronto para merge" "→ Próximo: jaguar-beta: merjar o PRD #51 (validado em 22/10)"
tem "UNKNOWN persistente" "| STG | 🟡 aberto | calculando (UNKNOWN) |"
tem "sem topologia" "ℹ outro: topologia do flow ausente"
tem "referências sem URL" "(referências sem URL ignoradas: #99)"
tem "tudo merjado" "pode fechar: \`orq fechar d-refs\`"
igual "PR repetido no arquivo aparece uma vez" "$(echo "$out" | grep -c '\[#91\]')" 1
nao "concluída fica fora" "## d-feita"
nao "demanda sem prs fica fora" "## d-semprs"
tem "resumo" "**Agora:** 15 demanda(s) · 28 PRs · 16 merjados · 1 pronto(s) para merge · 1 com conflito · 2 alerta(s) de deploy"
tem "primeira execução" "sem execução anterior"
out="$(prs --todas 2>&1)"; tem "--todas inclui concluída" "## d-feita — concluida"
out="$(prs d-semprs 2>&1)"; tem "slug sem prs" "Sem PRs com URL"
out="$(prs 2>&1)"; tem "segunda execução: nada mudou" "nada mudou"
jq '."11".state = "MERGED" | ."11".mergedAt = "2099-01-01T00:00:00Z" | ."11".mergedBy = {login: "rev"}' "$FX/jaguar-beta.json" > "$FX/x" && mv "$FX/x" "$FX/jaguar-beta.json"
cp "$EP/.prs-ultimo.json" "$T/cache-antes"
out="$(prs --json 2>&1)"
cmp -s "$EP/.prs-ultimo.json" "$T/cache-antes" && ok "--json não grava cache" || nok "--json gravou cache"
echo "$out" | jq -e '.demandas | length == 15' >/dev/null && ok "--json é JSON" || nok "--json: $out"
cp "$EP/.prs-ultimo.json" "$T/cache-antes"
out="$(prs d-ordem 2>&1)"
cmp -s "$EP/.prs-ultimo.json" "$T/cache-antes" && ok "execução com slug não avança o cache" || nok "slug gravou cache"
out="$(prs 2>&1)"; tem "merge novo desde a última execução" "jaguar-beta#11 merjado por @rev"
tem "conflito some com o merge" "[#11](https://github.com/o/r/pull/11) | PRD | ✅ merjado"
rm -f "$STUB_DIR"/gh-*
out="$(STUB_GH_FALHAS=1 prs d-conflito 2>&1)"; tem "502 com nova tentativa" "## d-conflito"
igual "duas chamadas no 502" "$(wc -l < "$STUB_DIR/gh-calls" | tr -d ' ')" 2
cp "$EP/.prs-ultimo.json" "$T/cache-antes"
out="$(STUB_GH_FALHA_REPO=outro prs 2>&1)"; tem "repo que não responde não derruba o resto" "⚠ outro: GitHub não respondeu"
cmp -s "$EP/.prs-ultimo.json" "$T/cache-antes" && ok "execução com repo em falha não avança o cache" || nok "falha gravou cache"
tem "o resto continua" "## d-ordem"
deve_falhar "slug inexistente" "não existe" prs fantasma
deve_falhar "outros comandos ainda exigem herdr" "herdr" env -u ORQ_HERDR -u HERDR_ENV "$ORQ" status

echo "painel"
# os testes do prs merjaram o #11; o painel parte das fixtures originais
for r in jaguar-plus jaguar-beta outro unico; do jq -n -f "$AQUI/fixtures/prs.jq" | jq --arg r "$r" '.[$r]' > "$FX/$r.json"; done
printf '## O que é\nX\n\n## O que foi feito\nIntro\n- item a\n- item `b`\n' > "$EP/d-semval/resumo.md"
printf '# Brief — Título do brief\n\nresto\n' > "$EP/d-conflito/brief.md"
printf '## O que é\nFiltro <script>alert(1)</script> quebrado\n\n## O que foi feito\nCorrigimos o `filtro`.\n' > "$EP/d-pronto/resumo.md"
printf '2026-11-01 10:00:00 nova\n2026-11-02 11:30:00 implementando -> pr-aberto | https://x/1\nhttps://x/2\n' > "$EP/d-pronto/historico"
painel() { env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EP" ORQ_PRS_ESPERAS="0 0" ORQ_PRS_ESPERA_UNKNOWN=0 \
  ORQ_GH="$AQUI/gh-stub" ORQ_PAINEL=1 "$ORQ" painel "$@"; }
rm -f "$STUB_DIR"/gh-*
out="$(painel 2>&1)" && ok "painel roda fora do herdr" || nok "painel: $out"
echo "$out" | grep -q "file://$EP/painel.html" && ok "imprime o caminho do índice" || nok "caminho: $out"
I="$EP/painel.html"; PC="$EP/d-conflito/resumo.html"; PP="$EP/d-pronto/resumo.html"
[ -s "$I" ] && [ -s "$PC" ] && [ -s "$EP/d-feita/resumo.html" ] && ok "índice e uma página por demanda" || nok "páginas não geradas"
contem() { grep -qF -- "$3" "$2" && ok "$1" || nok "$1 — não achei em $(basename "$(dirname "$2")")/$(basename "$2"): $3"; }
naocontem() { grep -qF -- "$3" "$2" && nok "$1 — achei: $3" || ok "$1"; }
externos="$(cat "$EP"/painel.html "$EP"/*/resumo.html | grep -oE '(src|href)="[^"]*"' | grep -E '"(https?:)?//' | grep -v 'https://github.com/' || true)"
igual "nenhum recurso externo além de links do GitHub" "$externos" ""
contem "card linka a página da demanda" "$I" 'href="d-conflito/resumo.html"'
contem "página volta ao índice" "$PC" 'href="../painel.html"'
contem "sem resumo.md cai no título do brief" "$I" "Título do brief"
PV="$EP/d-semval/resumo.html"
contem "alerta na página da demanda" "$PV" "PRD aberto sem <code>validado</code>"
contem "conflito na página da demanda" "$PC" "⚠ CONFLITO"
contem "papel do PR" "$PC" '#11</a> <span class="fase">PRD</span>'
contem "arquivos agrupados por prefixo" "$PP" "db/functions/fn_x_*.sql</code> (4)"
contem "lista completa expansível" "$PP" "<li>db/functions/fn_x_c.sql</li>"
contem "pasta com até 2 arquivos lista o caminho" "$PP" "<code>src/app.ts</code>"
contem "resumo.md: o que foi feito" "$PP" "Corrigimos o <code>filtro</code>."
contem "texto escapado" "$PP" "Filtro &lt;script&gt;alert(1)&lt;/script&gt; quebrado"
naocontem "nada de script vindo do resumo" "$PP" "<script>alert"
contem "nota de várias linhas fica numa entrada só" "$PP" "https://x/1 · https://x/2"
contem "mudou em vem do histórico" "$I" "mudou 02/11 11:30"
contem "spec-pronto é com você" "$I" '<span class="quem q-você">você</span>aprovar ou ajustar o spec'
contem "concluídas recolhidas" "$I" 'Concluídas (1)'
grep -qw 80 "$STUB_DIR/gh-calls" && nok "concluída não vai ao GitHub" || ok "concluída não vai ao GitHub"
contem "hora da leitura dos PRs" "$I" "PRs lidos em"
[ -s "$EP/.painel-prs.json" ] && ok "guarda a última leitura boa" || nok "sem .painel-prs.json"

contem "lista do resumo.md vira lista" "$EP/d-semval/resumo.html" "<p>Intro</p><ul><li>item a</li><li>item <code>b</code></li></ul>"
cp -R "$EP" "$T/ep-novo"; rm -f "$T/ep-novo/.painel-prs.json"
env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$T/ep-novo" ORQ_PRS_ESPERAS="0 0" ORQ_PRS_ESPERA_UNKNOWN=0 STUB_GH_FALHA_REPO=jaguar-beta \
  ORQ_GH="$AQUI/gh-stub" "$ORQ" painel >/dev/null 2>&1
contem "repo em falha sem leitura anterior não finge leitura" "$T/ep-novo/d-semval/resumo.html" "sem leitura do GitHub"
echo concluida > "$T/ep-novo/d-semval/estado"
env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$T/ep-novo" ORQ_GH="$AQUI/gh-stub" "$ORQ" painel --local >/dev/null 2>&1
cp -R "$EP" "$T/ep-concl"   # .painel-prs.json daqui tem d-conflito em CONFLITO
grep -q CONFLITO "$T/ep-concl/d-conflito/resumo.html" && ok "pré-condição: leitura guardada tem o conflito" || nok "pré-condição do conflito"
echo concluida > "$T/ep-concl/d-conflito/estado"
env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$T/ep-concl" ORQ_GH="$AQUI/gh-stub" "$ORQ" painel --local >/dev/null 2>&1
naocontem "concluída não usa leitura antiga do GitHub" "$T/ep-concl/d-conflito/resumo.html" "CONFLITO"
printf '%s\n' "https://github.com/onebeatco/jaguar-beta/pull/12" > "$T/ep-concl/d-semval/prs"
env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$T/ep-concl" ORQ_GH="$AQUI/gh-stub" "$ORQ" painel --local >/dev/null 2>&1
contem "links regravados invalidam a leitura guardada" "$T/ep-concl/d-semval/resumo.html" "não lido do GitHub"
echo '{"demandas":[1]}' > "$T/ep-concl/.painel-prs.json"; rm -f "$T/ep-concl/painel.html"
env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$T/ep-concl" ORQ_GH="$AQUI/gh-stub" "$ORQ" painel --local >/dev/null 2>&1
[ -s "$T/ep-concl/painel.html" ] && ok "cache corrompido não trava o painel" || nok "cache corrompido travou o painel"
out="$(STUB_GH_FALHA_REPO=jaguar-beta painel 2>&1)" || nok "painel com repo fora: $out"
contem "aviso quando um repo não responde" "$I" "GitHub não respondeu para jaguar-beta"
contem "demanda do repo fora mantém a leitura anterior" "$PV" "PRD aberto sem <code>validado</code>"
contem "e avisa que é leitura anterior" "$PV" "O GitHub não respondeu na última leitura"

rm -f "$STUB_DIR"/gh-*; rm -f "$I"
env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EP" ORQ_GH="$AQUI/gh-stub" ORQ_PAINEL=1 "$ORQ" painel --local >/dev/null 2>&1
[ -s "$I" ] && [ ! -e "$STUB_DIR/gh-calls" ] && ok "--local não chama o GitHub" || nok "--local"
contem "--local usa a leitura guardada" "$PV" "PRD aberto sem <code>validado</code>"

rm -f "$I" "$STUB_DIR"/gh-*
out="$(env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EP" ORQ_PRS_ESPERAS="0 0" ORQ_PRS_ESPERA_UNKNOWN=0 \
  ORQ_GH="$AQUI/gh-stub" ORQ_PAINEL=1 "$ORQ" prs 2>&1)"
[ -s "$I" ] && ok "orq prs completo regrava o painel" || nok "orq prs não regravou o painel"
igual "sem chamada extra ao GitHub" "$(grep -c completa "$STUB_DIR/gh-calls")" 4

rm -f "$I" "$STUB_DIR"/gh-*; echo "spec" > "$EP/d-semprs/spec.md"
ORQ_ESTADO="$EP" ORQ_GH="$AQUI/gh-stub" "$ORQ" estado d-semprs investigando "ajuste" >/dev/null 2>&1
sleep 2; [ ! -e "$I" ] && ok "ORQ_PAINEL=0 não regrava" || nok "ORQ_PAINEL=0 regravou"
out="$(ORQ_ESTADO="$EP" ORQ_GH="$AQUI/gh-stub" ORQ_PAINEL=1 ORQ_PAPEL=lider "$ORQ" estado d-semprs spec-pronto 2>&1)"
echo "$out" | grep -q "aviso: falta .*d-semprs/resumo.md" && ok "avisa resumo.md ausente" || nok "aviso resumo: $out"
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$I" ] && break; sleep 0.5; done
[ -s "$I" ] && ok "orq estado regrava o painel em segundo plano" || nok "estado não regravou"
[ ! -e "$STUB_DIR/gh-calls" ] && ok "estado não chama o GitHub" || nok "estado chamou o GitHub"

echo
echo "quadro (fila do flow)"
EQ="$T/estado-quadro"; FX2="$T/fixtures-quadro"; FF="$T/fila-fixtures"; mkdir -p "$EQ" "$FX2" "$FF"
# plugin falso: o de usuário (0.39.2) e um de projeto antigo, que não pode ser usado
for v in user:0.39.2 proj:0.20.1; do
  d="$T/plugin-${v%%:*}"; mkdir -p "$d/skills/flow/scripts" "$d/.claude-plugin"; : > "$d/skills/flow/scripts/flow-queue.mjs"
  jq -n --arg v "${v##*:}" '{version: $v}' > "$d/.claude-plugin/plugin.json"
done
jq -n --arg u "$T/plugin-user" --arg p "$T/plugin-proj" '{plugins: {"jaguar-plus@onebeat": [
  {scope: "project", projectPath: "/x", installPath: $p, version: "0.20.1"},
  {scope: "user", installPath: $u, version: "0.39.2"}]}}' > "$T/plugins.json"
for r in jaguar-plus jaguar-beta jaguar-plus-frontend; do jq -n -f "$AQUI/fixtures/fila.jq" | jq --arg r "$r" '.[$r]' > "$FF/$r.json"; done
mkdir -p "$ORQ_RAIZ/jaguar-plus-frontend/.claude/flow"
echo '{"hml":"staging","prod":"master","migracao_automatica":true,"migracao_paths":[]}' > "$ORQ_RAIZ/jaguar-plus-frontend/.claude/flow/topology.json"

# repo git do patch-id: #330 = aprovado + merge da base (mesmo diff); #340 = aprovado + mudança nova
O="$T/origem-beta.git"; W="$T/w-beta"; git init -q --bare "$O"; git init -q "$W"
gw() { git -C "$W" -c user.email=t@t -c user.name=t "$@"; }
gw checkout -q -b staging; echo base > "$W/base.txt"; gw add .; gw commit -q -m c0
gw checkout -q -b f330; echo um > "$W/a.txt"; gw add .; gw commit -q -m c1; SHA330="$(gw rev-parse --short=8 HEAD)"
gw checkout -q staging; echo mais > "$W/b.txt"; gw add .; gw commit -q -m c2
gw checkout -q f330; gw merge -q --no-edit staging
gw checkout -q -b f340 staging~1; echo dois > "$W/c.txt"; gw add .; gw commit -q -m c3; SHA340="$(gw rev-parse --short=8 HEAD)"
echo tres > "$W/d.txt"; gw add .; gw commit -q -m c4
gw push -q "$O" staging f330:refs/pull/330/head f340:refs/pull/340/head
rm -rf "$ORQ_RAIZ/jaguar-beta/.git"; git init -q "$ORQ_RAIZ/jaguar-beta"; git -C "$ORQ_RAIZ/jaguar-beta" remote add origin "$O"

for r in jaguar-plus jaguar-beta jaguar-plus-frontend; do
  jq -n -f "$AQUI/fixtures/prs-quadro.jq" | jq --arg r "$r" '.[$r]' \
    | sed -e "s/__SHA330__/$SHA330/" -e "s/__SHA340__/$SHA340/" > "$FX2/$r.json"
done
P=https://github.com/onebeatco/jaguar-plus/pull; B=https://github.com/onebeatco/jaguar-beta/pull
F=https://github.com/onebeatco/jaguar-plus-frontend/pull
demq() { local s="$1" f="$2"; shift 2; mkdir -p "$EQ/$s"; echo "$f" > "$EQ/$s/estado"; : > "$EQ/$s/agentes"
  echo "2026-11-12 10:00:00 x -> $f" > "$EQ/$s/historico"; [ $# -eq 0 ] || printf '%s\n' "$@" > "$EQ/$s/prs"; }
demq q-prio pr-aberto "$P/200 [STG]" "$P/201" "$B/300" "$B/301"
demq q-val pr-aberto "$P/212" "$P/213" "$B/310" "$B/311"
demq q-stg pr-aberto "$P/220" "$P/221" "$B/320" "$B/321"
demq q-fechado pr-aberto "$P/230" "$P/231"
demq q-dep pr-aberto "$P/240" "$P/241"
demq q-desat pr-aberto "$B/330" "$B/331" "$B/340" "$B/341"
demq q-front pr-aberto "$F/400 (só HML)" "$F/401" "$F/405" "$F/402" "$F/406" "$F/403" "$F/407"
demq q-spec spec-pronto
demq q-impl implementando
demq q-feita concluida "$P/230"

quadro() { env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EQ" ORQ_PRS_ESPERAS="0 0" ORQ_PRS_ESPERA_UNKNOWN=0 \
  ORQ_GH="$AQUI/gh-stub" GH_FIXTURES="$FX2" FILA_FIXTURES="$FF" ORQ_PLUGINS_JSON="$T/plugins.json" "$ORQ" prs --quadro "$@"; }
rm -f "$STUB_DIR"/gh-* "$STUB_DIR/fila-calls"
out="$(quadro 2>&1)" && ok "quadro roda fora do herdr" || nok "quadro: $out"
[ -n "${QUADRO_DUMP:-}" ] && echo "$out" > "$QUADRO_DUMP"
# snapshot: da tabela ao fim (o título e a linha de abertura têm hora); QUADRO_DUMP=arq regrava a referência
igual "snapshot do quadro" "$(echo "$out" | sed 1,4d)" "$(cat "$AQUI/fixtures/quadro.esperado")"
linha() { echo "$out" | grep -F -- "**$1**"; }
tem_l() { linha "$2" | grep -qF -- "$3" && ok "$1" || nok "$1 — linha $2: $(linha "$2")"; }
nao_l() { linha "$2" | grep -qF -- "$3" && nok "$1 — linha $2: $(linha "$2")" || ok "$1"; }
igual "fila chamada uma vez por repo" "$(sort "$STUB_DIR/fila-calls" | awk '{print $1}' | tr '\n' ' ')" "jaguar-beta jaguar-plus jaguar-plus-frontend "
grep -q "plugin-user" "$STUB_DIR/fila-calls" && ! grep -q "plugin-proj" "$STUB_DIR/fila-calls" \
  && ok "usa o plugin do escopo de usuário, nunca o de projeto" || nok "caminho do plugin: $(cat "$STUB_DIR/fila-calls")"
tem "título com a hora da fila" "· fila do flow de"
tem "primeira execução" "Primeira consulta."
tem "cabeçalho da tabela" "| # | Demanda | Situação | Próximo passo / quem |"
tem_l "Espera: o beta não é 'merjar'" q-prio "beta #300 aprovado, ⏸ em Espera do plus #200 (HML)"
tem_l "o plus que segura recebe o review" q-prio "**Igor:** review plus #200"
nao_l "Espera não vira merjar" q-prio "merjar beta #300"
tem "recado com o que segura" "Review plus #200 (q-prio): segura o beta #300"
tem_l "PRD posterior antes do anterior em PRD é ⚠" q-val "⚠ **Guilherme:** merjar beta #311 (PRD) (só depois do plus aplicado em PRD)"
tem_l "conflito no PRD é ⚠ e decisão" q-val "⚠ **Você:** resolver o conflito do beta #311 (PRD)"
tem "conflito no PRD em decisões" "q-val: resolver o conflito do beta #311 (PRD)"
tem_l "STG fora de ordem é só ℹ" q-stg "ℹ STG do beta pode entrar antes do plus"
tem_l "conflito no STG é só ℹ" q-stg "ℹ beta #320 (STG) em conflito"
nao_l "nada de STG gera ⚠" q-stg "⚠"
tem_l "fora da fila e merjado: ciclo fechado" q-fechado "| ✅ Tudo em PRD | Pode fechar (\`orq fechar q-fechado\`)"
tem_l "7b é ⚠ com o comando" q-dep "⚠ **Igor:** rodar \`/deploy production\` do plus #241"
tem_l "aprovação vale com patch-id igual" q-desat "ℹ aprovação do beta #330 vale: a head só trouxe merge da base"
nao_l "patch-id diferente: a aprovação não é dada como válida" q-desat "#340 vale"
[ -z "$(git -C "$ORQ_RAIZ/jaguar-beta" for-each-ref refs/orq)" ] && ok "refs/orq/* apagadas" || nok "sobrou ref em refs/orq"
tem_l "só HML por desenho" q-front "ℹ só HML por desenho: par incompleto esperado"
tem_l "só HML vira review do revisor" q-front "review plus-front (api+admin) #400"
tem "recado do só HML" "Review plus-front (api+admin) #400, só HML por desenho (q-front)"
tem_l "área: só bull" q-front "**CS:** validar plus-front (bull) #401 em HML"
tem_l "4 áreas: sem rótulo" q-front "review plus-front #402"
tem_l "lista truncada: sem rótulo" q-front "review plus-front #403"
nao "nunca 'bull' como nome do repo" "bull #"
tem_l "spec-pronto sem prs" q-spec "| Spec pronto | **Você:** aprovar ou ajustar o spec |"
tem "spec-pronto em decisões" "q-spec: spec pronto esperando aprovação."
tem_l "implementando com o líder" q-impl "| Implementando | **Líder:** implementando |"
nao "concluída fica fora" "q-feita"
tem "aviso do plugin no rodapé, uma vez" "ℹ plugin jaguar-plus@onebeat 0.39.2 instalado, 0.39.3 publicada"
igual "aviso do plugin não repete" "$(echo "$out" | grep -c '0.39.3 publicada')" 1
ordem="$(echo "$out" | grep -E '^\| [0-9]+ \|' | sed -E 's/^\| [0-9]+ \| \*\*([^*]+)\*\*.*/\1/' | tr '\n' ' ')"
case "$ordem" in "q-fechado q-dep "*"q-spec q-impl ") ok "ordem: mais perto de PRD primeiro, sem PR no fim" ;; *) nok "ordem: $ordem" ;; esac

echo "quadro: idempotência e cache"
rm -f "$STUB_DIR/fila-calls"; o1="$out"
out="$(quadro 2>&1)"
[ ! -s "$STUB_DIR/fila-calls" ] && ok "dentro do TTL não roda a fila" || nok "rodou a fila dentro do TTL"
igual "segunda execução igual (fora título e abertura)" "$(echo "$out" | sed '1,3d')" "$(echo "$o1" | sed '1,3d')"
tem "segunda execução: nada andou" "Nada andou desde"
out="$(ORQ_FILA_TTL_MIN=0 quadro 2>&1)"
igual "fora do TTL roda uma vez por repo" "$(wc -l < "$STUB_DIR/fila-calls" | tr -d ' ')" 3
rm -f "$STUB_DIR/fila-calls"
out="$(ORQ_FILA_TTL_MIN=0 quadro --rapido 2>&1)"
[ ! -s "$STUB_DIR/fila-calls" ] && ok "--rapido não roda a fila" || nok "--rapido rodou a fila"
tem_l "--rapido usa o cache" q-prio "⏸ em Espera do plus #200"
out="$(env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EQ" "$ORQ" fila 2>&1)"; tem "orq fila mostra a idade" "jaguar-plus: cache de 0 min"

echo "quadro: fallback"
fallback() { # descrição padrão-do-motivo env...
  local d="$1" pad="$2"; shift 2
  rm -rf "$EQ/.fila"
  out="$(env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EQ" \
    ORQ_PRS_ESPERAS="0 0" ORQ_PRS_ESPERA_UNKNOWN=0 ORQ_GH="$AQUI/gh-stub" GH_FIXTURES="$FX2" FILA_FIXTURES="$FF" \
    ORQ_PLUGINS_JSON="$T/plugins.json" ORQ_FILA_TIMEOUT=1 "$@" "$ORQ" prs --quadro 2>&1)"
  tem_l "$d: cai na heurística com ℹ" q-prio "ℹ fila do flow indisponível em plus — passo pela heurística do orq"
  out2="$(env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EQ" ORQ_PRS_ESPERAS="0 0" ORQ_PRS_ESPERA_UNKNOWN=0 ORQ_GH="$AQUI/gh-stub" \
    GH_FIXTURES="$FX2" FILA_FIXTURES="$FF" ORQ_PLUGINS_JSON="$T/plugins.json" ORQ_FILA_TIMEOUT=1 "$@" "$ORQ" prs q-prio 2>&1)"
  echo "$out2" | grep -q "fila do flow indisponível ($pad" && ok "$d: motivo no detalhe" || nok "$d: motivo — $(echo "$out2" | grep ℹ)"
}
fallback "plugin ausente" "plugin jaguar-plus não instalado" ORQ_PLUGINS_JSON="$T/nao-existe.json"
jq '.version = "0.30.1"' "$T/plugin-user/.claude-plugin/plugin.json" > "$T/x" && cp "$T/plugin-user/.claude-plugin/plugin.json" "$T/pj" && mv "$T/x" "$T/plugin-user/.claude-plugin/plugin.json"
fallback "versão abaixo da mínima" "plugin jaguar-plus 0.30.1 abaixo da mínima 0.39.2"
cp "$T/pj" "$T/plugin-user/.claude-plugin/plugin.json"
fallback "fila com rc≠0" "a fila saiu com rc=3" STUB_FILA_RC=3
fallback "timeout" "a fila passou de 1s" STUB_FILA_SLEEP=3
fallback "formato mudou" "formato da fila mudou" STUB_FILA_QUEBRADO=1
nao "heurística: rodapé avisa" "Situação e próximo passo vêm da fila"
quadro >/dev/null 2>&1   # cache bom
out="$(ORQ_FILA_TTL_MIN=0 STUB_FILA_RC=3 quadro 2>&1)"
tem_l "fila falhou com cache recente: usa o cache e diz" q-prio "ℹ fila de 0 min atrás: a fila saiu com rc=3"
tem_l "cache velho mantém o passo da fila" q-prio "⏸ em Espera do plus #200"

echo "dois marcadores no mesmo comentário"
out="$(env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EQ" ORQ_PRS_ESPERAS="0 0" ORQ_PRS_ESPERA_UNKNOWN=0 ORQ_GH="$AQUI/gh-stub" \
  GH_FIXTURES="$FX2" "$ORQ" prs q-fechado --json --sem-fila 2>&1)"
igual "deploy_hml + deploy_prod do mesmo comentário" "$(echo "$out" | jq -r '[.demandas[0].prs[] | select(.number == 231) | .eventos[].type] | join(" ")')" "deploy_hml deploy_prod"
igual "nenhum alerta de deploy no PRD" "$(echo "$out" | jq '[.demandas[0].repos[].alertas[] | select(.tipo == "deploy")] | length')" 0
igual "marcador quebrado ignorado sozinho" "$(echo "$out" | jq '[.demandas[0].prs[] | select(.number == 231) | .eventos[]] | length')" 2

echo "nota"
out="$(env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EQ" "$ORQ" nota q-fechado "CS: conferir filtros em PRD" 2>&1)"; tem "grava" "nota gravada"
out="$(quadro 2>&1)"; tem_l "aparece na célula" q-fechado "📝 *CS: conferir filtros em PRD* (nota"
nao_l "nota nova não é antiga" q-fechado "(antiga)"
touch -t 202611010000 "$EQ/q-fechado/nota"
out="$(quadro 2>&1)"; tem_l "nota anterior à última mudança é antiga" q-fechado "(antiga)"
env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EQ" "$ORQ" nota q-dep "decisão: esperar a janela de deploy" >/dev/null
out="$(quadro 2>&1)"; tem "nota 'decisão:' vira decisão" "q-dep: esperar a janela de deploy"
env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EQ" "$ORQ" nota q-fechado - >/dev/null
[ ! -e "$EQ/q-fechado/nota" ] && ok "apaga" || nok "nota não apagada"
deve_falhar "nota sem texto" "uso" env -u ORQ_HERDR -u HERDR_ENV ORQ_ESTADO="$EQ" "$ORQ" nota q-fechado

echo "github no esperar"
ogh() { env ORQ_ESTADO="$EQ" ORQ_RAIZ="$ORQ_RAIZ" ORQ_PRS_ESPERAS="0 0" ORQ_PRS_ESPERA_UNKNOWN=0 ORQ_GH="$AQUI/gh-stub" \
  GH_FIXTURES="$FX2" "$@" "$AQUI/../scripts/orq-github"; }
rm -f "$EQ/.github-visto.json"
out="$(ogh 2>&1)"; igual "primeira rodada só grava a base" "$out" ""
[ -s "$EQ/.github-visto.json" ] && ok "estado visto persistido" || nok "sem .github-visto.json"
jq '."200".reviews.nodes = [{state: "CHANGES_REQUESTED", submittedAt: "2026-11-13T15:00:00Z", author: {login: "guilhermesjlender-1beat"}}]
  | ."200".comments.nodes += [{createdAt: "2026-11-13T15:01:00Z", author: {login: "igormeloonebeat", __typename: "User"}, body: "olha isso"}]
  | ."221".state = "OPEN" | ."221".mergeStateStatus = "DIRTY" | ."221".mergeable = "CONFLICTING"' "$FX2/jaguar-plus.json" > "$T/x" && mv "$T/x" "$FX2/jaguar-plus.json"
out="$(ogh 2>&1)"
tem "review do GitHub vira linha github" "github  q-prio  jaguar-plus#200  review @guilhermesjlender-1beat"
tem "comentário de revisor sem marcador" "github  q-prio  jaguar-plus#200  comentário @igormeloonebeat"
tem "conflito novo" "github  q-stg  jaguar-plus#221  conflito"
igual "uma linha por evento" "$(echo "$out" | grep -c '^github')" 3
out="$(ogh 2>&1)"; igual "rodada seguinte sem mudança: nada" "$out" ""
jq '."300".state = "MERGED" | ."300".mergedAt = "2026-11-13T16:00:00Z" | ."300".mergedBy = {login: "guilhermesjlender-1beat"}' \
  "$FX2/jaguar-beta.json" > "$T/x" && mv "$T/x" "$FX2/jaguar-beta.json"
out="$(ogh STUB_GH_FALHA_REPO=jaguar-beta 2>&1)"; igual "repo em falha não avisa" "$(echo "$out" | grep -c '^github')" 0
out="$(ogh 2>&1)"; tem "e não perde o evento na próxima" "github  q-prio  jaguar-beta#300  merjado @guilhermesjlender-1beat"
out="$(ogh 2>&1)"; igual "sem repetir" "$out" ""

# integração: o esperar global acorda com a linha github (o poll roda em segundo plano)
jq '."201".comments.nodes += [{createdAt: "2026-11-13T17:00:00Z", author: {login: "igormeloonebeat", __typename: "User"},
  body: "<!-- flow:event {\"type\":\"aprovado\",\"at\":\"2026-11-13T17:00:00Z\",\"actor\":\"igormeloonebeat\"} -->"}]' \
  "$FX2/jaguar-plus.json" > "$T/x" && mv "$T/x" "$FX2/jaguar-plus.json"
rm -f "$EQ/.github-poll.em" "$EQ/.snap-global"
out="$(ORQ_ESTADO="$EQ" ORQ_GITHUB_INTERVALO=1 ORQ_GH="$AQUI/gh-stub" GH_FIXTURES="$FX2" ORQ_PRS_ESPERAS="0 0" \
  ORQ_PRS_ESPERA_UNKNOWN=0 ORQ_PLUGINS_JSON="$T/nao-existe.json" "$ORQ" esperar --max 15 2>&1)"
tem "esperar acorda com github" "github  q-prio  jaguar-plus#201  aprovado @igormeloonebeat"
sleep 1; [ -e "$EQ/.fila/jaguar-plus.invalido" ] && ok "evento invalida o cache da fila do repo" || nok "fila não invalidada"
[ ! -e "$EQ/.fila/jaguar-beta.invalido" ] && ok "e só do repo do evento" || nok "invalidou repo sem evento"

if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
