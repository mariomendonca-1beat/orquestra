#!/usr/bin/env bash
# Testes do orq com um herdr falso e repos git temporários.  Uso: bash tests/run.sh
set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
ORQ="$AQUI/../scripts/orq"
HOME_ORQ="$(cd "$AQUI/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export STUB_DIR="$T/stub" ORQ_HERDR="$AQUI/herdr-stub" ORQ_RAIZ="$T/raiz" ORQ_INTERVALO=1
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
for r in jaguar-plus jaguar-beta outro; do jq -n -f "$AQUI/fixtures/prs.jq" | jq --arg r "$r" '.[$r]' > "$FX/$r.json"; done
mkdir -p "$ORQ_RAIZ/jaguar-plus/.claude/flow" "$ORQ_RAIZ/jaguar-beta/.claude/flow"
echo '{"hml":"staging","prod":"production","migracao_automatica":false,"migracao_paths":["*.sql"],
  "migracao_cmd":{"hml":"/deploy staging","prod":"/deploy production"}}' > "$ORQ_RAIZ/jaguar-plus/.claude/flow/topology.json"
echo '{"hml":"staging","prod":"master","migracao_automatica":true,"migracao_paths":[]}' > "$ORQ_RAIZ/jaguar-beta/.claude/flow/topology.json"
dem() { # slug fase linha-do-prs...
  local s="$1" f="$2"; shift 2; mkdir -p "$EP/$s"; echo "$f" > "$EP/$s/estado"; printf '%s\n' "$@" > "$EP/$s/prs"; }
B=https://github.com/onebeatco/jaguar-beta/pull; P=https://github.com/onebeatco/jaguar-plus/pull
dem d-conflito pr-aberto "$B/10 (HML)" "$B/11 (PROD)"
dem d-ordem pr-aberto "$P/20" "$P/21"
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
  ORQ_GH="$AQUI/gh-stub" "$ORQ" prs "$@"; }
rm -f "$STUB_DIR"/gh-*
out="$(prs 2>&1)" && ok "prs roda fora do herdr" || nok "prs fora do herdr: $out"
igual "uma chamada completa por repo" "$(grep -c completa "$STUB_DIR/gh-calls")" 3
igual "UNKNOWN re-consulta só os abertos UNKNOWN" "$(grep leve "$STUB_DIR/gh-calls" | sort -u | tr '\n' '|')" "jaguar-beta leve 51 60 |jaguar-beta leve 60 |"
tem() { echo "$out" | grep -qF -- "$2" && ok "$1" || nok "$1 — não achei: $2"; }
nao() { echo "$out" | grep -qF -- "$2" && nok "$1 — achei: $2" || ok "$1"; }
tem "conflito" "⚠ jaguar-beta#11: em conflito com \`master\`"
tem "passo do conflito" "→ Próximo: jaguar-beta: resolver o conflito de #11"
tem "ordem quebrada" "⚠ jaguar-plus#21: ordem quebrada"
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
tem "resumo" "**Agora:** 9 demanda(s) · 17 PRs · 10 merjados · 1 pronto(s) para merge · 1 com conflito · 2 alerta(s) de deploy"
tem "primeira execução" "sem execução anterior"
out="$(prs --todas 2>&1)"; tem "--todas inclui concluída" "## d-feita — concluida"
out="$(prs d-semprs 2>&1)"; tem "slug sem prs" "Sem PRs com URL"
out="$(prs 2>&1)"; tem "segunda execução: nada mudou" "nada mudou"
jq '."11".state = "MERGED" | ."11".mergedAt = "2099-01-01T00:00:00Z" | ."11".mergedBy = {login: "rev"}' "$FX/jaguar-beta.json" > "$FX/x" && mv "$FX/x" "$FX/jaguar-beta.json"
cp "$EP/.prs-ultimo.json" "$T/cache-antes"
out="$(prs --json 2>&1)"
cmp -s "$EP/.prs-ultimo.json" "$T/cache-antes" && ok "--json não grava cache" || nok "--json gravou cache"
echo "$out" | jq -e '.demandas | length == 9' >/dev/null && ok "--json é JSON" || nok "--json: $out"
out="$(prs 2>&1)"; tem "merge novo desde a última execução" "jaguar-beta#11 merjado por @rev"
tem "conflito some com o merge" "[#11](https://github.com/o/r/pull/11) | PRD | ✅ merjado"
rm -f "$STUB_DIR"/gh-*
out="$(STUB_GH_FALHAS=1 prs d-conflito 2>&1)"; tem "502 com nova tentativa" "## d-conflito"
igual "duas chamadas no 502" "$(wc -l < "$STUB_DIR/gh-calls" | tr -d ' ')" 2
out="$(STUB_GH_FALHA_REPO=outro prs 2>&1)"; tem "repo que não responde não derruba o resto" "⚠ outro: GitHub não respondeu"
tem "o resto continua" "## d-ordem"
deve_falhar "slug inexistente" "não existe" prs fantasma
deve_falhar "outros comandos ainda exigem herdr" "herdr" env -u ORQ_HERDR -u HERDR_ENV "$ORQ" status

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
