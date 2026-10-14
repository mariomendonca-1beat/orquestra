#!/usr/bin/env bash
# Testes do orq com um herdr falso e repos git temporários.  Uso: bash tests/run.sh
set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
ORQ="$AQUI/../scripts/orq"
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
grep -q "workspace create .*--label pivot - lider" "$STUB_DIR/calls" && ok "workspace rotulado" || nok "workspace rotulado"
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
echo sujo > "$ORQ_RAIZ/jaguar-plus-frontend-wt-pivot/arq"
out="$("$ORQ" fechar pivot 2>&1)"
echo "$out" | grep -q "mantida .*frontend-wt-pivot: tem mudanças" && ok "mantém worktree suja" || nok "worktree suja: $out"
echo "$out" | grep -q "mantida .*jaguar-plus-wt-pivot: branch sem upstream" && ok "mantém branch sem push" || nok "sem upstream: $out"
igual "fase final" "$(cat "$ESTADO/pivot/estado")" concluida

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
