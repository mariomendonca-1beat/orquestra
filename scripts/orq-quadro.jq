# Lógica pura do quadro (`orq prs --quadro`): recebe a análise do orq-prs.jq (com a fila do flow
# já cruzada em cada repo) e devolve o markdown do quadro. Uso:
#   jq -r -L scripts 'include "orq-quadro"; quadro($cfg; $locais; $aprovacoes)' analise.json
#   $cfg        — config/pessoas.json
#   $locais     — {slug: {mudou, nota: {texto, em} | null}}
#   $aprovacoes — {"repo#n": true|false}: aprovado_desatualizado só por merge da base (patch-id igual)
#
# Regras (spec prs-quadro v2): Situação = o repo menos avançado; Próximo = um item por repo na
# ordem de merge; ⚠ só para risco de quebrar PRD, ℹ para o resto; recados por pessoa; decisões.

def hora: localtime | strftime("%H:%M");
def diames: localtime | strftime("%d/%m");

# progresso rumo a PRD (não é a ORDEM_ESTADOS do flow, que é ordem de atenção)
def RANK: {"0": 0, "1": 0, "2": 1, "3": 2, "4": 2, "4a": 2, "5": 3, "5b": 4, "5c": 4, "6a": 4, "6": 5,
           "6p-r": 5, "6b": 6, "6p": 6, "ORDEM_QUEBRADA": 7, "7b": 7, "7c": 8, "8": 9, "fechado": 10};
def SITUACAO: {"2": "Sem PR / par incompleto", "3": "Em review", "4a": "Em review", "4": "Rodada de review a tratar",
  "5": "Aprovado, falta merjar STG", "5b": "Em STG, falta deploy HML", "6": "Em STG, falta validar",
  "6a": "Correção pendente em STG", "6b": "✅ Validado pelo CS", "6p": "✅ Validado", "ORDEM_QUEBRADA": "⚠ Ordem quebrada",
  "7b": "Em PRD, falta deploy", "7c": "Em PRD, Pipeline rodando", "8": "Em PRD, falta merge-back", "fechado": "✅ Tudo em PRD"};
def FASES: {"nova": "Nova", "investigando": "Investigando", "spec-pronto": "Spec pronto", "aprovado": "Aprovado",
  "implementando": "Implementando", "pr-aberto": "PR aberto", "concluida": "Concluída"};

def nome_repo($cfg): . as $r | ($cfg.repos[$r].curto // $r);
def pessoa_login($cfg): . as $l | ($cfg.logins[$l] // "@\($l)");

# "plus-front (bull) #496": a área só quando o repo declara `areas` e o PR não toca todas (nem veio truncado)
def rot_pr($cfg; $prs; $repo; $n):
  ($cfg.repos[$repo].areas // null) as $areas
  | ([$prs[] | select(.repo == $repo and .number == $n)] | first // null) as $p
  | ( if $areas == null or $p == null or (($p.arquivosTotal // 0) > ($p.arquivos // [] | length)) then ""
      else ([$areas | to_entries[] | .key as $k | select(any($p.arquivos[]?; startswith($k))) | .value]) as $a
           | if ($a | length) == 0 or ($a | length) == ($areas | length) then "" else " (\($a | join("+")))" end end ) as $area
  | "\($repo | nome_repo($cfg))\($area) #\($n)";

def eh_comando: test("^(/|pr-|flow |orq )");
def soHML: test("(?i)\\(\\s*(só HML|so HML|revert)");

# um item do Próximo: {repo, pr, pessoa, texto, nivel: "alerta"|"normal"|"info", rank, decisao, segura, fase}
def itens_fila($cfg; $d; $r; $apr):
  [ $r.fila[] as $it
    | (if $it.acao == "publicar_prod" or ($it.state | IN("6b", "6p", "7b", "7c", "8")) then ($it.prod // $it.hml)
       else ($it.hml // $it.prod) end) as $n
    | ([$d.prs[] | select(.repo == $r.repo and .number == $n) | .anot] | first // "") as $anot
    | rot_pr($cfg; $d.prs; $r.repo; $n) as $rot
    | ($cfg.repos[$r.repo] // {}) as $pr
    | (if ($it.comando // "") | eh_comando then " (`\($it.comando)`)" else "" end) as $cmd
    | if $it.espera.em_espera == true then
        ($it.espera.raizes // []) as $raizes
        | ([$raizes[] | select(.numero) | {repo: (.repo // "" | split("/") | last), n: .numero}]) as $rs
        | ([$rs[] | select(. as $x | any($d.prs[]; .repo == $x.repo and .number == $x.n))] | length > 0) as $interna
        | (($it.espera.ambiente // "") | ascii_upcase | test("PRO")) as $prod
        | {repo: $r.repo, pr: $n, rank: ($it.state | RANK[.] // 2), state: $it.state,
           pessoa: (if $interna then null
                    elif $it.espera.cobranca.papel == "autor" then ($it.espera.cobranca.login // "" | pessoa_login($cfg))
                    else ($pr.revisa // "?") end),
           texto: "\($rot) \($it.rotulo // $it.label), ⏸ em Espera do \([$rs[] | rot_pr($cfg; $d.prs; .repo; .n)] | join(", ") | if . == "" then "dependência sem PR" else . end)\(if $prod then " (PROD)" else " (HML)" end)",
           nivel: (if $prod then "alerta" else "normal" end), decisao: (($rs | length) == 0),
           espera: $rs, rot: $rot, recado: (if $interna then null else "Destravar a Espera de \($rot)" end)}
      elif $it.state == "2" and $it.prod == null and ($anot | soHML) then
        {repo: $r.repo, pr: $n, rank: RANK["4a"], state: "4a", pessoa: ($pr.revisa // "?"),
         texto: "review \($rot)", recado: "Review \($rot), só HML por desenho",
         info: (($anot | gsub("^\\(|\\)$"; "") | sub("^s[óo] HML[;,:]? *"; ""; "i")) as $t
                | "só HML por desenho\(if $t == "" then "" else " (\($t))" end): par incompleto esperado"),
         nivel: "normal"}
      else
        ( if $it.vez.papel == "revisor" then
            if ($it.comando // "") | test("^/deploy") then {p: ($pr.deploya // $pr.merja // "?"), a: "rodar `\($it.comando)` do \($rot)"}
            elif $it.acao == "revisar" or $it.comando == "pr-review" then {p: ($pr.revisa // "?"), a: "review \($rot)\(if ($it.rotulo // "") | test("rodada [2-9]") then " (\($it.rotulo))" else "" end)"}
            elif $it.acao == "publicar_hml" then {p: ($pr.merja // "?"), a: "merjar \($rot) (STG\(if $it.rotulo == "aprovado" then ", aprovado" else "" end))"}
            elif $it.acao == "publicar_prod" then {p: ($pr.merja // "?"), a: "merjar \($rot) (PRD)"}
            else {p: ($pr.revisa // "?"), a: "\($it.label) — \($rot)\($cmd)"} end
          elif $it.acao == "validar" then {p: $cfg.validacao, a: "validar \($rot) em HML\($cmd)"}
          elif $it.acao == "tratar_rodada" then {p: $cfg.voce, a: "tratar a rodada do \($rot)\($cmd)"}
          else {p: $cfg.voce, a: "\($it.label) — \($rot)\($cmd)"} end ) as $q
        | {repo: $r.repo, pr: $n, rank: ($it.state | RANK[.] // 2), state: $it.state, pessoa: $q.p, texto: $q.a,
           nivel: (if ($it.state | IN("7b", "ORDEM_QUEBRADA")) or $it.alerta == true then "alerta" else "normal" end),
           decisao: ($it.state == "ORDEM_QUEBRADA"),
           acao: $it.acao,
           info: (if $apr["\($r.repo)#\($n)"] == true then "aprovação do \($rot) vale: a head só trouxe merge da base" else null end)}
      end ];

# fallback: o passo da heurística do orq-prs, com a pessoa por palavra-chave
def itens_heuristica($cfg; $d; $r):
  ($cfg.repos[$r.repo] // {}) as $pr
  | ([$r.alertas[] | select(.tipo | IN("conflito", "ordem", "ordem-sem-stg", "deploy", "sem-validado"))
      | select(.tipo != "conflito" or .pr.papel == "PRD") | select(.tipo != "deploy" or .amb == "PRD")] | length > 0) as $risco
  | if $r.passo == null then []
    else ($r.passo) as $t
    | [ { repo: $r.repo, pr: null, texto: $t,
          rank: (if $t | test("^aplicar a migração") then 7 elif $t | test("^merjar o PRD") then 6
                 elif $t | test("^validar") then 5 elif $t | test("aprovado: merjar") then 3 else 2 end),
          state: null,
          pessoa: (if $t | test("conflito|ordem quebrada|abrir o PRD|regravar") then $cfg.voce
                   elif $t | test("migração") then ($pr.deploya // $pr.merja // "?")
                   elif $t | test("^validar") then $cfg.validacao
                   elif $t | test("merjar|aprovado") then ($pr.merja // "?") else ($pr.revisa // "?") end),
          nivel: (if $risco then "alerta" else "normal" end),
          decisao: ($t | test("conflito|ordem quebrada")),
          acao: (if $t | test("merjar o PRD") then "publicar_prod" elif $t | test("aprovado: merjar") then "publicar_hml" else null end),
          info: null } ]
    end;

def linha_item: (if .nivel == "alerta" then "⚠ " else "" end)
  + (if .pessoa then "**\(.pessoa):** " else "" end) + .texto;
# itens seguidos da mesma pessoa se juntam: "**Guilherme:** merjar beta #330 · merjar beta #340"
def linhas_juntas: reduce .[] as $x ([]; if length > 0 and .[-1].pessoa == $x.pessoa and $x.pessoa != null
    then .[-1].textos += [$x.texto] else . + [{pessoa: $x.pessoa, textos: [$x.texto]}] end)
  | map((if .pessoa then "**\(.pessoa):** " else "" end) + (.textos | join(" · ")));

def demanda($cfg; $loc; $apr; $agora):
  . as $d
  | ($loc[$d.slug] // {}) as $l
  | ($cfg.ordemMerge // []) as $ordem
  | [ $d.repos[] as $r
      | if $r.falhou then {repo: $r.repo, falha: true, rank: 2, itens: [], infos: ["GitHub não respondeu (\($r.repo | nome_repo($cfg)))"]}
        elif $r.origem == "fila" and ($r.cicloFechado // false) then {repo: $r.repo, rank: RANK.fechado, itens: [], infos: []}
        elif $r.origem == "fila" then
          # o que a fila não cobre e o GitHub mostra: conflito (⚠ só no PRD), ordem quebrada, base estranha
          ([ $r.alertas[] | select(.tipo | IN("conflito", "ordem", "ordem-sem-stg", "base", "erro"))
             | . as $al | rot_pr($cfg; $d.prs; $r.repo; $al.pr.number) as $rot
             | if .tipo == "conflito" and .pr.papel != "PRD" then {info: "\($rot) (STG) em conflito"}
               else {repo: $r.repo, pr: $al.pr.number, rank: 99, pessoa: $cfg.voce, nivel: "alerta", decisao: true,
                     texto: (if .tipo == "conflito" then "resolver o conflito do \($rot) (PRD)" else "\($rot): \(.msg)" end)} end ]) as $extra
          | ((itens_fila($cfg; $d; $r; $apr)) + [$extra[] | select(.texto)]) as $its
          | ($its + [$extra[] | select(.texto | not)]) as $its
          | {repo: $r.repo, rank: ([$its[].rank] | min // RANK.fechado), state: ([$its[] | {rank, state}] | min_by(.rank) | .state // null),
             itens: $its, infos: ([$its[].info | select(. != null)] + (if $r.filaMotivo then [$r.filaMotivo] else [] end))}
        else
          (itens_heuristica($cfg; $d; $r)) as $its
          | {repo: $r.repo, rank: ([$its[].rank] | min // RANK.fechado), state: null, itens: $its, heur: true,
             infos: (if $r.filaMotivo then ["fila do flow indisponível em \($r.repo | nome_repo($cfg)) — passo pela heurística do orq"] else [] end)}
        end ]
  | sort_by(.repo as $x | ($ordem | index($x)) // 99) as $repos
  # ordem entre repos: PRD de um repo posterior antes do anterior aplicado em PRD = ⚠ (risco de PRD);
  # STG posterior antes do anterior = ℹ (normal). Com a fila, a Espera declarada já cobre o caso.
  | [ range(0; $repos | length) as $i | $repos[$i]
      | . as $cur
      | ([$repos[:$i][] | select(.rank < RANK["7c"] and (.falha | not))] | first // null) as $ant
      | .itens |= map(
          if $ant == null or .espera != null then .
          elif .acao == "publicar_prod" then .nivel = "alerta" | .texto += " (só depois do \($ant.repo | nome_repo($cfg)) aplicado em PRD)"
          elif .acao == "publicar_hml" and $ant.rank < RANK["6"] then .info = "STG do \($cur.repo | nome_repo($cfg)) pode entrar antes do \($ant.repo | nome_repo($cfg))"
          else . end)
      | .infos = ([.itens[].info | select(. != null)] + .infos | unique) ] as $repos
  | ($repos | map(.rank) | min // null) as $rk
  | ([$repos[] | select(.rank == $rk)] | first // null) as $menos
  | ( if ($d.prs | length) == 0 then (FASES[$d.fase] // $d.fase)
      elif $rk == RANK.fechado then SITUACAO.fechado
      elif $menos.state != null then (SITUACAO[$menos.state] // ([$menos.itens[] | .state] | first) // "Em andamento")
      else ({"1": "Em review", "2": "Em review", "3": "Aprovado, falta merjar STG", "5": "Em STG, falta validar",
             "6": "✅ Validado pelo CS", "7": "Em PRD, falta deploy"}["\($rk)"] // "Em andamento") end ) as $sit
  | ([$repos[].itens[]]) as $itens
  | ( if ($d.prs | length) == 0 then
        (if $d.fase == "spec-pronto" then [{pessoa: $cfg.voce, texto: "aprovar ou ajustar o spec", nivel: "normal", decisao: true}]
         else [{pessoa: $cfg.lider, texto: (FASES[$d.fase] // $d.fase | ascii_downcase), nivel: "normal"}] end)
      else $itens end ) as $itens
  | ($l.nota // null) as $nota
  | ([$d.prs[] | (.mergedAt // 0), (.eventos[]?.at // 0)] + [$l.mudou // 0] | max) as $ultMud
  | { slug: $d.slug, fase: $d.fase, rank: (if ($d.prs | length) == 0 then (if $d.fase == "spec-pronto" then -1 else -2 end) else $rk end),
      mudou: ($ultMud // 0), situacao: $sit, itens: $itens,
      celula: (
        ( [ $itens[] | select(.nivel == "alerta" and .texto != null) | linha_item ]
        + [ $repos[] | [ .itens[] | select(.nivel != "alerta" and .texto != null) ] | sort_by(.pessoa // "")
            | linhas_juntas | select(length > 0) | join(" · ") ] | join(" → ") ) as $p
        | ( [ $repos[].infos[] | "ℹ \(.)" ] | unique | join(" · ") ) as $i
        | ( if $p == "" and ($d.prs | length) > 0 and $rk == RANK.fechado then "Pode fechar (`orq fechar \($d.slug)`)"
            elif $p == "" and ($d.prs | length) == 0 then ($itens | map(linha_item) | join(" · "))
            else $p end ) as $p
        | [$p, $i, (if $nota then "📝 *\($nota.texto)* (nota \($nota.em | diames))\(if $ultMud > $nota.em then " (antiga)" else "" end)" else "" end)]
        | map(select(. != "")) | join(" · ") ),
      nota: $nota };

def mudanca_txt($cfg):
  gsub("@(?<l>[A-Za-z0-9_-]+)"; (.l | pessoa_login($cfg)))
  | gsub("(?<r>jaguar-[a-z-]+)#"; ((.r | nome_repo($cfg)) + " #"));

def quadro($cfg; $loc; $apr):
  . as $a
  | $a.geradoEm as $agora
  | [ $a.demandas[] | demanda($cfg; $loc; $apr; $agora) ] as $ds
  | ($ds | sort_by([-(.rank), -(.mudou)])) as $ds
  | ([$ds[] | .itens[] | select(.texto != null and .pessoa != null and .pessoa != $cfg.voce and .pessoa != $cfg.lider and .pessoa != "?")]) as $pend
  | ([$ds[].itens[] | select(.espera != null) | . as $e | .espera[] | {repo, n, rot: $e.rot}]) as $segura
  | ([$pend[].pessoa] | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)) as $pessoas
  | ([$a.demandas[].repos[] | select(.origem == "fila" and .filaIdade != null) | .filaIdade] | max // null) as $idade
  | ([$a.demandas[].repos[] | select(.origem == "heuristica" and .filaMotivo != null)] | length > 0) as $heur
  | "# Demandas — \($agora | localtime | strftime("%d/%m %H:%M"))\(if $idade != null then " · fila do flow de \(($agora - $idade * 60) | hora)\(if $idade >= 15 then " (\($idade) min atrás)" else "" end)" else "" end)",
    "",
    ( if $a.desde == null then "Primeira consulta."
      elif ($a.mudancas | length) == 0 then
        "Nada andou desde \($a.desde | hora)\(if ($pessoas | length) > 0 then " — tudo depende de \($pessoas | if length > 1 then (.[:-1] | join(", ")) + " e " + .[-1] else .[0] end)" else "" end)."
      else "Desde \($a.desde | localtime | strftime("%d/%m %H:%M")): " + ($a.mudancas[:3] | map(mudanca_txt($cfg)) | join("; "))
           + (if ($a.mudancas | length) > 3 then " (+\(($a.mudancas | length) - 3))" else "" end) + "." end ),
    "",
    ( if ($ds | length) == 0 then "Nenhuma demanda em voo."
      else
        "| # | Demanda | Situação | Próximo passo / quem |",
        "|---|---|---|---|",
        ( range(0; $ds | length) as $i | $ds[$i] | "| \($i + 1) | **\(.slug)** | \(.situacao) | \(.celula) |" )
      end ),
    "",
    ( if ($pessoas | length) > 0 then
        "**Recados prontos**", "",
        ( $pessoas[] as $p
          | "- **\($p)**",
            ( $ds[] as $d | $d.itens[] | select(.pessoa == $p and .texto != null) | . as $it
              | (.recado // .texto) as $t
              | ([$segura[] | select(.repo == $it.repo and .n == $it.pr) | .rot] | unique) as $sg
              | "  - \($t | (.[:1] | ascii_upcase) + .[1:]) (\($d.slug))\(if ($sg | length) > 0 then ": segura o \($sg | join(", "))" else "" end)" ) ),
        ""
      else empty end ),
    "**Decisões pendentes suas**", "",
    ( [ $ds[] as $d
        | ( if $d.rank == -1 then "\($d.slug): spec pronto esperando aprovação." else empty end ),
          ( $d.itens[] | select(.decisao == true and .pessoa == $cfg.voce and $d.rank != -1) | "\($d.slug): \(.texto)" ),
          ( $d.itens[] | select(.decisao == true and .espera != null and (.espera | length) == 0) | "\($d.slug): \(.texto) — combinar com quem segura" ),
          ( if ($d.nota.texto // "") | test("^decis[aã]o:"; "i") then "\($d.slug): \($d.nota.texto | sub("^decis[aã]o: *"; ""; "i"))" else empty end ) ]
      | if length == 0 then "Nenhuma decisão pendente sua agora."
        else to_entries[] | "\(.key + 1). \(.value)" end ),
    "",
    ( [ $a.demandas[].repos[].filaAvisos[]? ] | unique[] | "ℹ \(.)" ),
    ( if $heur then "_ℹ marca passo vindo da heurística do orq (fila do flow indisponível); o resto vem da fila do `/jaguar-plus:flow`._"
      else "_Situação e próximo passo vêm da fila do `/jaguar-plus:flow`; pessoas em `config/pessoas.json`._" end );
