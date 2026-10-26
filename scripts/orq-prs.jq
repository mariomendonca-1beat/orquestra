# Lógica pura do `orq prs`: recebe {agora, demandas, dados, falhas, topo, cache} montado pelo
# orq-prs e devolve a análise (`analisar`) e o markdown (`markdown`). Eventos seguem o
# protocolo flow:event do jaguar-plus (referencia-eventos.md da skill flow).

def ts: if . == null then null else sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 end;
def quando: if . == null then "?" else localtime | strftime("%d/%m %H:%M") end;
def dia: if . == null then "?" else localtime | strftime("%d/%m") end;
def maximo: if length == 0 then null else max end;

# glob da topologia (migracao_paths) -> regex. Sem "/", casa o nome do arquivo em qualquer
# pasta (o "*.sql" do jaguar-plus); com "/", casa o caminho inteiro e "**" atravessa pastas.
def glob_re:
  (gsub("\\."; "\\.") | gsub("\\*\\*"; "\u0001") | gsub("\\*"; "[^/]*") | gsub("\u0001"; ".*")) as $r
  | if test("/") then "^" + $r + "$" else "(^|/)" + $r + "$" end;

def eventos($n):
  [ .comments.nodes[]? | select((.author.__typename // "") != "Bot") | . as $c
    | (try (.body | capture("<!-- flow:event (?<j>\\{.*?\\}) -->").j | fromjson) catch null)
    | select(type == "object" and .type != null)
    | { type, pr: $n, actor: (.actor // $c.author.login),
        at: ((try (.at | ts) catch null) // ($c.createdAt | ts)) } ];

def normalizar($owner; $repo; $n; $topo):
  if . == null then {owner: $owner, repo: $repo, number: $n, erro: "não encontrado", eventos: []}
  else . as $p | {
    owner: $owner, repo: $repo, number: $n, url, title, state, draft: .isDraft,
    base: .baseRefName, mergedAt: (.mergedAt | ts), mergedBy: .mergedBy.login,
    mergeable, mss: .mergeStateStatus,
    papel: (if $topo == null then "?" elif .baseRefName == $topo.hml then "STG"
            elif .baseRefName == $topo.prod then "PRD" else "base " + .baseRefName end),
    conflito: (.state == "OPEN" and (.mergeable == "CONFLICTING" or .mergeStateStatus == "DIRTY")),
    tocaMigracao: ($topo != null and $topo.migracao_automatica == false
      and ([$p.files.nodes[]?.path] as $ps | any(($topo.migracao_paths // [])[] | glob_re; . as $re | any($ps[]; test($re))))),
    truncado: ((.comments.totalCount // 0) > (.comments.nodes // [] | length)),
    eventos: eventos($n) }
  end;

def rotulo: "\(.repo)#\(.number)";
def ultimo($evs; $tipo): [$evs[] | select(.type == $tipo) | .at] | maximo;
def lista: map("#\(.number)") | join(", ");

# um repo de uma demanda: alertas por PR, próximo passo, prontos para merge
def analisar_repo($prs; $topo):
  ([$prs[].eventos[]] | sort_by(.at)) as $evs
  | [$prs[] | select(.erro == null and .state != "CLOSED")] as $vivos
  | [$vivos[] | select(.papel == "STG")] as $stg
  | [$vivos[] | select(.papel == "PRD")] as $prd
  | ([$stg[] | select(.state == "MERGED") | .mergedAt] | maximo) as $stgM
  | (ultimo($evs; "validado")) as $val
  | ($stgM != null and $val != null and $val > $stgM) as $validado
  | (ultimo($evs; "aprovado")) as $apr
  | ([ultimo($evs; "review"), ultimo($evs; "reprovado")] | map(select(. != null)) | maximo) as $rev
  | ($apr != null and ($rev == null or $apr > $rev)) as $aprovado
  | ($rev != null and ($apr == null or $rev > $apr)
     and ($rev > ([ultimo($evs; "selfreview")] | map(select(. != null)) | maximo // 0))) as $rodada
  | ($topo.migracao_cmd // {}) as $cmd
  | [ $prs[] as $p
      | ( if $p.erro then {pr: $p, tipo: "erro", msg: "PR não encontrado no GitHub"} else empty end ),
        ( if $p.conflito then {pr: $p, tipo: "conflito", msg: "em conflito com `\($p.base)`"} else empty end ),
        ( if $p.papel == "PRD" and $p.state == "MERGED" and ($stg | length) == 0
          then {pr: $p, tipo: "ordem-sem-stg", msg: "PRD merjado e nenhum STG do repo listado na demanda: ordem não verificada"}
          else empty end ),
        ( if $p.papel == "PRD" and $p.state == "MERGED" and ($stg | length) > 0
             and ([$stg[] | select(.state == "MERGED" and .mergedAt <= $p.mergedAt)] | length) == 0
          then ($stgM != null) as $depois
               | {pr: $p, tipo: (if $depois then "ordem-tardia" else "ordem" end),
                  msg: ("ordem quebrada: PRD merjado antes de qualquer STG do repo (E-011)"
                        + (if $depois then "; o STG entrou depois (\($stgM | quando))" else "" end))}
          else empty end ),
        ( if $p.state == "MERGED" and $p.tocaMigracao and ($p.papel == "STG" or $p.papel == "PRD") then
            (if $p.papel == "STG" then "deploy_hml" else "deploy_prod" end) as $ev
            | (if $p.papel == "STG" then $cmd.hml else $cmd.prod end) as $c
            | if ([$evs[] | select(.type == $ev and .at > $p.mergedAt)] | length) == 0
              then {pr: $p, tipo: "deploy", amb: $p.papel, cmd: $c,
                    msg: "merjado sem `\($ev)`: migração não registrada como aplicada\(if $c then " (`\($c)`)" else "" end)"}
              else empty end
          else empty end ),
        ( if $p.papel == "PRD" and $p.state == "OPEN" and $stgM != null and ($validado | not)
          then {pr: $p, tipo: "sem-validado", msg: "PRD aberto sem `validado` posterior ao merge do STG"} else empty end ),
        ( if $p.papel == "PRD" and $p.state == "MERGED" and $stgM != null
             and ([$evs[] | select(.type == "validado" and .at > $stgM)] | length) == 0
          then {pr: $p, tipo: "info", msg: "validação pulada: PRD merjado sem `validado` posterior ao merge do STG"} else empty end ),
        ( if ($p.papel | startswith("base ")) and $p.state != "CLOSED"
          then {pr: $p, tipo: "base", msg: "base `\($p.base)` não é a de HML nem a de PROD da topologia"} else empty end ),
        ( if $p.truncado then {pr: $p, tipo: "info", msg: "mais de 60 comentários: eventos antigos não lidos"} else empty end )
    ] as $alertas
  | ([$alertas[] | select(.tipo == "deploy")]) as $deploys
  | ([$stg[] | select(.state == "OPEN")]) as $stgA
  | ([$prd[] | select(.state == "OPEN")]) as $prdA
  | { eventos: $evs, alertas: $alertas, ultimoEvento: ($evs | last),
      prontos: ( [ $stgA[] | select(.mss | IN("CLEAN", "HAS_HOOKS", "BLOCKED")) | select($aprovado) ]
               + [ $prdA[] | select(.mss | IN("CLEAN", "HAS_HOOKS", "BLOCKED")) | select($validado
                     and ([$deploys[] | select(.amb == "STG")] | length) == 0) ] ),
      passo: (
        if $topo == null then
          (if ([$vivos[] | select(.state == "OPEN")] | length) > 0
           then "\([$vivos[] | select(.state == "OPEN")] | lista) aberto (repo sem topologia do flow)" else null end)
        elif ([$alertas[] | select(.tipo == "conflito")] | length) > 0 then
          "resolver o conflito de \([$alertas[] | select(.tipo == "conflito") | .pr] | lista)"
        elif ([$alertas[] | select(.tipo == "ordem")] | length) > 0 then
          "ordem quebrada em \([$alertas[] | select(.tipo == "ordem") | .pr] | lista): merjar o STG\(if ($stgA | length) > 0 then " " + ($stgA | lista) else "" end) e conferir o ambiente de HML (E-011)"
        elif ($deploys | length) > 0 then
          "aplicar a migração: " + ([$deploys[] | "\(.cmd // "aplicar e registrar o `deploy_\(.amb | if . == "STG" then "hml" else "prod" end)`") (#\(.pr.number))"] | join(", "))
        elif ($stgA | length) > 0 then
          if $aprovado then "STG \($stgA | lista) aprovado: merjar"
          elif $rodada then "STG \($stgA | lista): rodada de review a tratar"
          else "STG \($stgA | lista) aguarda review/merge" end
        elif ($prdA | length) > 0 and $stgM == null then
          "PRD \($prdA | lista) aberto, sem STG merjado listado na demanda"
        elif ($prdA | length) > 0 and ($validado | not) then
          "validar em HML e registrar `flow validado`; depois merjar o PRD \($prdA | lista)"
        elif ($prdA | length) > 0 then
          "merjar o PRD \($prdA | lista) (validado em \($val | dia))"
        else null end) };

def analisar:
  . as $in
  | ($in.cache.em // null) as $desde
  | [ $in.demandas[] as $d
      | [ $d.refs[] as $r | ($in.topo[$r.repo]) as $topo
          | if $in.falhas["\($r.owner)/\($r.repo)"] then
              {owner: $r.owner, repo: $r.repo, number: $r.number, falhou: true, eventos: []}
            else ($in.dados["\($r.owner)/\($r.repo)"]["p\($r.number)"] | normalizar($r.owner; $r.repo; $r.number; $topo)) end
        ] as $prs
      | ([$prs[] | "\(.owner)/\(.repo)"] | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)) as $ordemRepos
      | { slug: $d.slug, fase: $d.fase, ignoradas: $d.ignoradas, prs: $prs,
          repos: [ $ordemRepos[] as $or
                   | ($or | split("/")[1]) as $nome
                   | if $in.falhas[$or] then {repo: $nome, falhou: $in.falhas[$or], alertas: [], prontos: [], passo: null}
                     else ([$prs[] | select("\(.owner)/\(.repo)" == $or)] as $rp
                           | {repo: $nome, semTopologia: ($in.topo[$nome] == null)} + analisar_repo($rp; $in.topo[$nome])) end ] } ]
  as $dems
  | [$dems[].prs[] | select(.falhou | not)] as $todos
  | ($todos | unique_by([.owner, .repo, .number])) as $unicos
  | { geradoEm: $in.agora, desde: $desde, demandas: $dems,
      resumo: { demandas: ($dems | length), prs: ($unicos | length),
                merjados: ([$unicos[] | select(.state == "MERGED")] | length),
                prontos: ([$dems[].repos[].prontos[] | rotulo] | unique | length),
                conflito: ([$unicos[] | select(.conflito)] | length),
                deploy: ([$dems[].repos[].alertas[] | select(.tipo == "deploy") | .pr | rotulo] | unique | length) },
      mudancas: (if $desde == null then null else
        ( [ $unicos[] | select(.state == "MERGED" and .mergedAt > $desde)
            | {at: .mergedAt, txt: "\(rotulo) merjado por @\(.mergedBy // "?") (\(.mergedAt | quando))"} ]
        + [ $unicos[] as $p | $p.eventos[] | select(.at > $desde)
            | {at, txt: "`\(.type)` em \($p.repo)#\(.pr) por @\(.actor) (\(.at | quando))"} ]
        + [ $unicos[] | . as $p | ($in.cache.prs["\(.owner)/\(rotulo)"] // null) as $c | select($c != null)
            | (if $c.state == "OPEN" and $p.state == "CLOSED" then {at: $in.agora, txt: "\(rotulo) fechado sem merge"} else empty end),
              (if ($c.conflito | not) and $p.conflito then {at: $in.agora, txt: "\(rotulo) ficou em conflito"} else empty end),
              (if $c.conflito and ($p.conflito | not) and $p.state == "OPEN" then {at: $in.agora, txt: "\(rotulo) saiu do conflito"} else empty end) ]
        | unique_by(.txt) | sort_by(.at) | map(.txt)) end),
      cacheNovo: { em: $in.agora,
        prs: (($in.cache.prs // {}) + ($unicos | map({key: "\(.owner)/\(rotulo)", value: {state, conflito}}) | from_entries)) } };

# --- markdown ---------------------------------------------------------------

def celula_estado:
  if .falhou then "⚠ GitHub não respondeu"
  elif .erro then "⚠ " + .erro
  elif .state == "MERGED" then "✅ merjado \(.mergedAt | quando) @\(.mergedBy // "?")"
  elif .state == "CLOSED" then "⛔ fechado sem merge"
  elif .draft then "🟡 aberto (rascunho)"
  else "🟡 aberto" end;

def celula_merge:
  if .state != "OPEN" then "—"
  elif .conflito then "⚠ CONFLITO"
  elif .mergeable == "UNKNOWN" or .mss == "UNKNOWN" then "calculando (UNKNOWN)"
  else {CLEAN: "CLEAN", HAS_HOOKS: "CLEAN", BLOCKED: "BLOCKED (falta aprovação)", BEHIND: "BEHIND",
        UNSTABLE: "UNSTABLE (checks)", DRAFT: "rascunho"}[.mss] // .mss end;

def markdown:
  . as $r
  | "# PRs das demandas — \($r.geradoEm | localtime | strftime("%Y-%m-%d %H:%M"))",
    "",
    ( if $r.desde == null then "**Desde a última execução:** sem execução anterior"
      elif ($r.mudancas | length) == 0 then "**Desde \($r.desde | quando):** nada mudou"
      else "**Desde \($r.desde | quando):** " + ($r.mudancas | join(" · ")) end ),
    "**Agora:** \($r.resumo.demandas) demanda(s) · \($r.resumo.prs) PRs · \($r.resumo.merjados) merjados · \($r.resumo.prontos) pronto(s) para merge · \($r.resumo.conflito) com conflito · \($r.resumo.deploy) alerta(s) de deploy",
    "",
    ( $r.demandas[] as $d
      | ([$d.repos[] | {key: .repo, value: .}] | from_entries) as $porRepo
      | "## \($d.slug) — \($d.fase)",
        "",
        ( if ($d.prs | length) == 0 then "Sem PRs com URL no arquivo `prs`."
          else
            "| Repo | PR | Papel | Estado | Merge | Último evento do repo |",
            "|---|---|---|---|---|---|",
            ( $d.prs[] | . as $p | ($porRepo[$p.repo].ultimoEvento) as $u
              | "| \($p.repo) | [#\($p.number)](\($p.url // "https://github.com/\($p.owner)/\($p.repo)/pull/\($p.number)")) | \($p.papel // "?") | \(celula_estado) | \(celula_merge) | \(if $u then "\($u.type) \($u.at | dia)" else "—" end) |" )
          end ),
        ( $d.repos[] | select(.falhou) | "⚠ \(.repo): GitHub não respondeu (\(.falhou))" ),
        ( $d.repos[] | select(.semTopologia) | "ℹ \(.repo): topologia do flow ausente no checkout local; sem papel STG/PRD nem alertas de ciclo" ),
        ( $d.repos[].alertas[] | "\(if .tipo == "info" then "ℹ" else "⚠" end) \(.pr | rotulo): \(.msg)" ),
        ( [ $d.repos[] | select(.passo != null) | {repo, passo} ] | group_by(.passo)
          | if length == 0 then
              (if ([$d.repos[] | select(.falhou)] | length) > 0 then "→ Próximo: indeterminado (GitHub não respondeu)"
               else "→ Próximo: tudo merjado e aplicado — pode fechar: `orq fechar \($d.slug)`" end)
            else "→ Próximo: " + (map("\(map(.repo) | join(", ")): \(.[0].passo)") | join("; ")) end ),
        ( if ($d.ignoradas | length) > 0 then "(referências sem URL ignoradas: \($d.ignoradas | map("#\(.)") | join(", ")))" else empty end ),
        "" ),
    "_Próximo passo é heurística deste relatório; o passo canônico de uma demanda é o `/jaguar-plus:flow` na branch dela._";
