# Render do `orq painel`: recebe os dados locais das demandas e a análise do `orq prs` (por slug,
# com a hora da leitura) e devolve as páginas como "caminho\0html\0". Reaproveita as células e
# datas do orq-prs.jq. Tudo que vem de arquivo ou do GitHub passa por `e` (escape HTML).
include "orq-prs";

def e: tostring | @html;
def codigo: e | gsub("`(?<c>[^`]+)`"; "<code>\(.c)</code>");
def hist_quando: if . == null or length < 16 then "?" else .[8:10] + "/" + .[5:7] + " " + .[11:16] end;

# --- resumo.md / brief.md ----------------------------------------------------

def secao($re):
  split("\n")
  | reduce .[] as $l ({em: false, out: []};
      if ($l | test("^#{1,6}\\s")) then .em = ($l | test($re; "i"))
      elif .em then .out += [$l | sub("^\\s+"; "") | sub("\\s+$"; "")] else . end)
  | .out | map(select(length > 0)) | join(" ") | if length == 0 then null else . end;

def linhas($re):
  split("\n")
  | reduce .[] as $l ({em: false, out: []};
      if ($l | test("^#{1,6}\\s")) then .em = ($l | test($re; "i"))
      elif .em then .out += [$l | sub("^\\s+"; "") | sub("\\s+$"; "")] else . end)
  | .out | map(select(length > 0));

def titulo_brief: sub("^#+\\s*"; "") | sub("^Brief\\s*[—–-]\\s*"; "") | if length == 0 then null else . end;

# --- arquivos ----------------------------------------------------------------

def dirn: split("/") | .[:-1] | join("/");
def base: split("/") | last;
def ext: (capture("(?<x>\\.[^./]+)$").x) // "";
def prefixo:
  . as $xs | $xs[0] as $a
  | first(range(0; ($a | length) + 1) as $i
          | select($i == ($a | length) or any($xs[]; .[$i:$i + 1] != $a[$i:$i + 1])) | $a[0:$i]);

# caminhos -> [{rotulo, n, lista}]: pasta com até 2 arquivos lista os caminhos; com mais, vira
# "pasta/<prefixo comum>*.<ext> (N)" (ou "pasta/ (N)" com extensões diferentes)
def grupos:
  unique | group_by(dirn)
  | map((.[0] | dirn) as $d
        | if length <= 2 then .[] | {rotulo: ., n: 1, lista: [.]}
          else (map(base)) as $bs | ($bs | map(ext) | unique) as $xs | ($bs | prefixo) as $p
            | {n: length, lista: .,
               rotulo: (if ($xs | length) == 1
                        then ($d | if . == "" then "" else . + "/" end)
                             + (if ($p | length) >= 3 then $p else "" end) + "*" + $xs[0]
                        elif $d == "" then "(raiz)" else $d + "/" end)}
          end);

# --- modelo de uma demanda ------------------------------------------------------

def fase_nome: {"nova": "nova", "investigando": "investigando", "spec-pronto": "spec pronto",
  "aprovado": "aprovado", "implementando": "implementando", "pr-aberto": "PR aberto",
  "concluida": "concluída"}[.] // .;

def quem_passo:
  if test("rodada de review a tratar|abrir o PRD|regravar") then "líder"
  elif test("repo sem topologia") then "?"
  elif test("aguarda review") then "revisor"
  else "você" end;

def links_locais:
  split("\n") | map(capture("https://github\\.com/(?<owner>[^/ ]+)/(?<repo>[^/ ]+)/pull/(?<n>[0-9]+)")
    | {owner, repo, number: (.n | tonumber), url: "https://github.com/\(.owner)/\(.repo)/pull/\(.n)"})
  | unique_by([.repo, .number]);

def modelo($c):
  . as $l
  | ($l.prs | links_locais | map([.repo, .number]) | sort) as $locais
  # concluída: só dados locais; links regravados depois da leitura: a leitura não vale mais
  | (if $l.fase == "concluida" then null
     elif $c[$l.slug] != null and ($locais | length) > 0
          and ([$c[$l.slug].analise.prs[] | [.repo, .number]] | unique | sort) != ($locais | unique)
     then null else $c[$l.slug] end) as $p
  # nota de várias linhas (os links do pr-aberto) continua na entrada anterior
  | ($l.historico | split("\n")
     | reduce .[] as $x ([]; if ($x | test("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}( |$)"))
                            then . + [{ts: $x[0:19], txt: $x[20:]}]
                            elif length > 0 and ($x | length) > 0 then .[-1].txt += " · " + $x else . end)) as $hist
  | ($p.analise // null) as $a
  | ([$a.repos[]? | select(.passo != null) | {repo, passo, quem: (.passo | quem_passo)}]) as $passos
  | ([$a.repos[]? | select(.falhou)] | length > 0) as $repoFalhou
  | (if $a then $a.prs else ($l.prs | links_locais) end) as $prs
  | { slug: $l.slug, fase: $l.fase, docs: $l.docs, historico: $hist,
      mudou: ($hist | last | .ts // null),
      oque: (($l.resumo | secao("^#+\\s*o que [eé]\\s*$")) // ($l.brief | titulo_brief) // "(sem descrição)"),
      feitoLinhas: ($l.resumo | linhas("^#+\\s*o que foi feito")),
      feito: ($l.resumo | secao("^#+\\s*o que foi feito")),
      temResumo: ($l.resumo | length > 0),
      dadosEm: $p.dadosEm, falhou: ($p.falhou // false), analise: ($a != null), prs: $prs,
      alertas: [$a.repos[]?.alertas[]? | {pr: (.pr | rotulo), tipo, msg}],
      arquivos: [ $prs | group_by(.repo)[] | {repo: .[0].repo, caminhos: ([.[].arquivos[]?] | unique),
                  truncado: any(.[]; (.arquivosTotal // 0) > (.arquivos // [] | length))}
                  | select(.caminhos | length > 0) ],
      passos: $passos }
  | . + ( if .fase == "spec-pronto" then {quem: "você", proximo: "aprovar ou ajustar o spec"}
          elif .fase == "concluida" then {quem: null, proximo: "concluída"}
          elif .fase == "pr-aberto" then
            if $a == null then {quem: "?", proximo: "PRs ainda não lidos: rode `orq painel`"}
            elif ($passos | length) == 0 then
              (if $repoFalhou then {quem: "?", proximo: "indeterminado (GitHub não respondeu)"}
               else {quem: "você", proximo: "tudo merjado e aplicado — pode fechar: `orq fechar \(.slug)`"} end)
            else {quem: (if any($passos[]; .quem == "você") then "você"
                         elif any($passos[]; .quem == "revisor") then "revisor" else "líder" end),
                  proximo: ($passos | map("\(.repo): \(.passo)") | join("; "))} end
          else {quem: "líder", proximo: ({"nova": "líder subindo", "investigando": "líder investigando e escrevendo o spec",
                 "aprovado": "líder vai começar a implementação", "implementando": "implementação em andamento"}[.fase]
                 // "fase \(.fase)")} end );

# --- HTML ---------------------------------------------------------------------

def css: "
:root{--bg:#f6f7f9;--card:#fff;--tx:#1d2330;--mut:#5f6b7a;--bd:#dde2e8;--lk:#1f5fbf;--code:#eef1f5;
--voce:#b4530a;--voce-bg:#fff1e3;--rev:#5b3fbf;--rev-bg:#efeafd;--lid:#2c6e49;--lid-bg:#e5f4ea;--warn:#a3271b;--warn-bg:#fdecea;
--f-inv:#8a94a6;--f-spec:#d98a00;--f-impl:#2f6fde;--f-pr:#7a4fd6;--f-ok:#9aa3ae}
@media (prefers-color-scheme:dark){:root{--bg:#12151b;--card:#1b2029;--tx:#e6e9ef;--mut:#9aa5b4;--bd:#2c3340;--lk:#7fb0ff;--code:#262d39;
--voce:#ffb26b;--voce-bg:#3a2714;--rev:#b9a5ff;--rev-bg:#2a2343;--lid:#8fd4a8;--lid-bg:#183323;--warn:#ff9b8f;--warn-bg:#3b1a17;
--f-inv:#6c7689;--f-spec:#e0a020;--f-impl:#5b8ff0;--f-pr:#9d7cf0;--f-ok:#59616d}}
*{box-sizing:border-box}[hidden]{display:none!important}
body{margin:0;background:var(--bg);color:var(--tx);font:15px/1.45 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif}
.wrap{max-width:920px;margin:0 auto;padding:20px 16px 40px}
h1{font-size:22px;margin:0 0 4px}h2{font-size:15px;margin:22px 0 8px;color:var(--mut);text-transform:uppercase;letter-spacing:.04em}
h3{font-size:14px;margin:14px 0 6px}a{color:var(--lk)}code{background:var(--code);padding:1px 5px;border-radius:4px;font-size:.92em;overflow-wrap:anywhere}
.meta{color:var(--mut);font-size:13px;margin:0}
input[type=search]{width:100%;margin:14px 0 6px;padding:10px 12px;border:1px solid var(--bd);border-radius:8px;background:var(--card);color:var(--tx);font-size:15px}
.aviso{background:var(--warn-bg);color:var(--warn);border-radius:8px;padding:10px 12px;margin:12px 0;font-size:14px}
.card{display:block;text-decoration:none;color:inherit;background:var(--card);border:1px solid var(--bd);border-left:5px solid var(--f-inv);
border-radius:10px;padding:12px 14px;margin:10px 0}
a.card:hover{border-color:var(--lk)}
.f-spec-pronto{border-left-color:var(--f-spec)}.f-aprovado,.f-implementando{border-left-color:var(--f-impl)}
.f-pr-aberto{border-left-color:var(--f-pr)}.f-concluida{border-left-color:var(--f-ok)}
.topo{display:flex;flex-wrap:wrap;gap:6px 10px;align-items:baseline}
.slug{font-weight:650;font-size:16px}.fase{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--mut)}
.quando{margin-left:auto;font-size:12px;color:var(--mut)}
.card p{margin:6px 0 0}.mini{font-size:13px;color:var(--mut)}
.quem{display:inline-block;font-size:12px;font-weight:600;border-radius:999px;padding:1px 8px;margin-right:6px}
.q-você{color:var(--voce);background:var(--voce-bg)}.q-revisor{color:var(--rev);background:var(--rev-bg)}
.q-líder{color:var(--lid);background:var(--lid-bg)}.q-x{color:var(--mut);background:var(--code)}
.warn{color:var(--warn)}
details{margin:6px 0}summary{cursor:pointer}
.concl summary{font-weight:600;padding:8px 0}
.tab{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:14px}
th,td{overflow-wrap:break-word;text-align:left;padding:6px 8px;border-bottom:1px solid var(--bd);vertical-align:top}th{color:var(--mut);font-weight:600}
ul{padding-left:20px;margin:4px 0}li{margin:2px 0;overflow-wrap:anywhere}
.lista{color:var(--mut);font-size:13px}
ol.hist{padding-left:0;list-style:none;font-size:13px}ol.hist li{padding:3px 0;border-bottom:1px dashed var(--bd)}
ol.hist .ts{color:var(--mut);margin-right:8px;white-space:nowrap}
@media (max-width:560px){table,tbody,tr,td{display:block}tr:first-child{display:none}tr{border-bottom:1px solid var(--bd);padding:6px 0}td{border:0;padding:1px 0}}
footer{margin-top:28px;color:var(--mut);font-size:12px}
";

def pagina($titulo; $corpo; $js):
  "<!doctype html>\n<html lang=\"pt-BR\"><head><meta charset=\"utf-8\">"
  + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
  + "<title>\($titulo | e)</title><style>\(css)</style></head>\n<body><div class=\"wrap\">\n"
  + $corpo + "\n<footer>Próximo passo e “com quem” são heurística deste painel; o passo canônico de uma demanda é o "
  + "<code>/jaguar-plus:flow</code> na branch dela.</footer></div>"
  + (if $js == "" then "" else "<script>\($js)</script>" end) + "</body></html>\n";

def chip_quem: if . == null then "" else "<span class=\"quem q-\(if . == "?" then "x" else . end)\">\(e)</span>" end;
def cls_fase: "f-" + (gsub("[^a-z-]"; ""));

def busca:
  [.slug, .oque, (.feito // ""), .fase, .proximo, (.prs[] | "\(.repo) #\(.number)"), (.arquivos[].caminhos[])] | join(" ");

def resumo_arquivos:
  [.arquivos[] | "\(.repo) \(.caminhos | length)\(if .truncado then "+" else "" end) arq."] | join(" · ");

def card:
  . as $m
  | "<a class=\"card \($m.fase | cls_fase)\" href=\"\($m.slug | @uri)/resumo.html\" data-busca=\"\($m | busca | e)\">"
  + "<div class=\"topo\"><span class=\"slug\">\($m.slug | e)</span><span class=\"fase\">\($m.fase | fase_nome | e)</span>"
  + "<span class=\"quando\">mudou \($m.mudou | hist_quando)</span></div>"
  + "<p>\($m.oque | codigo)</p>"
  + (if $m.fase == "concluida" then "" else "<p>\($m.quem | chip_quem)\($m.proximo | codigo)</p>" end)
  + ( [ (if ($m.prs | length) > 0 then "\($m.prs | length) PR(s)" else empty end),
        (([$m.alertas[] | select(.tipo != "info")] | length) as $n | if $n > 0 then "<span class=\"warn\">⚠ \($n) alerta(s)</span>" else empty end),
        (if ($m.arquivos | length) > 0 then ($m | resumo_arquivos | e) else empty end),
        (if $m.temResumo then empty else "sem resumo.md" end) ]
      | if length == 0 then "" else "<p class=\"mini\">" + join(" · ") + "</p>" end )
  + "</a>";

def js_busca: "const q=document.getElementById('q'),c=document.getElementById('concl');"
  + "q.addEventListener('input',()=>{const t=q.value.trim().toLowerCase();"
  + "document.querySelectorAll('[data-busca]').forEach(x=>{x.hidden=!!t&&!x.dataset.busca.toLowerCase().includes(t)});"
  + "if(c)c.open=!!t||c.dataset.aberto==='1'});"
  + "if(c)c.addEventListener('toggle',()=>{if(!q.value.trim())c.dataset.aberto=c.open?'1':'0'});";

def indice($ms; $aviso; $agora):
  ([$ms[] | select(.fase != "concluida")] | sort_by(.mudou // "") | reverse
   | sort_by(if .quem == "você" then 0 else 1 end)) as $ativos
  | ([$ms[] | select(.fase == "concluida")] | sort_by(.mudou // "") | reverse) as $feitas
  | ([$ms[].dadosEm | select(. != null)] | maximo) as $lido
  | pagina("Demandas";
      "<h1>Demandas</h1><p class=\"meta\">gerado \($agora | quando) · \($ativos | length) em voo · "
      + "\([$ativos[] | select(.quem == "você")] | length) com você · PRs lidos "
      + (if $lido then "em \($lido | quando)" else "nunca (rode <code>orq painel</code>)" end) + "</p>"
      + "<input id=\"q\" type=\"search\" placeholder=\"buscar: slug, texto, arquivo, nº do PR\" autocomplete=\"off\">"
      + (if $aviso != "" then "<div class=\"aviso\">⚠ \($aviso | e)</div>" else "" end)
      + (if ($ativos | length) == 0 then "<p class=\"meta\">Nenhuma demanda em voo.</p>" else ($ativos | map(card) | join("\n")) end)
      + (if ($feitas | length) > 0
         then "\n<details class=\"concl\" id=\"concl\" data-aberto=\"0\"><summary>Concluídas (\($feitas | length))</summary>"
              + ($feitas | map(card) | join("\n")) + "</details>"
         else "" end);
      js_busca);

def linha_pr:
  "<tr><td><b>\(.repo | e)</b> <a href=\"\(.url // "https://github.com/\(.owner)/\(.repo)/pull/\(.number)" | e)\" target=\"_blank\" rel=\"noopener\">#\(.number)</a>"
  + (if .papel then " <span class=\"fase\">\(.papel | e)</span>" else "" end)
  + (if .title then "<br><span class=\"lista\">\(.title | e)</span>" else "" end) + "</td>"
  + (if .state or .erro or .falhou then "<td>\(celula_estado | e)</td><td>\(celula_merge | e)</td>"
     else "<td colspan=\"2\" class=\"lista\">não lido do GitHub</td>" end) + "</tr>";

def item_grupo:
  if .n == 1 then "<li><code>\(.rotulo | e)</code></li>"
  else "<li><details><summary><code>\(.rotulo | e)</code> (\(.n))</summary><ul class=\"lista\">"
       + (.lista | map("<li>\(e)</li>") | join("")) + "</ul></details></li>" end;

# listas "- x" do resumo.md viram <ul>; o resto, parágrafo
def texto_feito:
  if .feito == null then "<p><span class=\"lista\">sem <code>resumo.md</code> ainda</span></p>"
  elif any(.feitoLinhas[]; test("^[-*] "))
  then ([.feitoLinhas[] | select(test("^[-*] ") | not)] | if length > 0 then "<p>\(join(" ") | codigo)</p>" else "" end)
       + "<ul>" + ([.feitoLinhas[] | select(test("^[-*] ")) | "<li>\(sub("^[-*] "; "") | codigo)</li>"] | join("")) + "</ul>"
  else "<p>\(.feito | codigo)</p>" end;

def detalhe($agora):
  . as $m
  | pagina("\($m.slug) — demanda";
      "<p class=\"meta\"><a href=\"../painel.html\">← todas as demandas</a></p>"
      + "<h1>\($m.slug | e)</h1><p class=\"meta\">\($m.fase | fase_nome | e) · mudou \($m.mudou | hist_quando) · página gerada \($agora | quando)</p>"
      + (if $m.falhou then "<div class=\"aviso\">⚠ O GitHub não respondeu na última leitura; PRs de \($m.dadosEm | quando).</div>" else "" end)
      + "<h2>O que é</h2><p>\($m.oque | codigo)</p>"
      + "<h2>O que foi feito</h2>" + texto_feito
      + (if $m.fase == "concluida" then "" else
          "<h2>Próximo</h2><p>\($m.quem | chip_quem)"
          + (if ($m.passos | length) > 1 then "</p><ul>" + ($m.passos | map("<li>\(.quem | chip_quem)<b>\(.repo | e)</b>: \(.passo | codigo)</li>") | join("")) + "</ul>"
             else "\($m.proximo | codigo)</p>" end) end)
      + "<h2>PRs</h2>"
      + (if ($m.prs | length) == 0 then "<p class=\"lista\">Nenhum PR registrado.</p>"
         else "<p class=\"meta\">\(if $m.analise then "lidos do GitHub em \($m.dadosEm | quando)" else "só os links do arquivo <code>prs</code> (sem leitura do GitHub)" end)</p>"
              + "<div class=\"tab\"><table><tr><th>PR</th><th>Estado</th><th>Merge</th></tr>"
              + ($m.prs | map(linha_pr) | join("")) + "</table></div>" end)
      + (if ($m.alertas | length) > 0
         then "<ul>" + ($m.alertas | map("<li class=\"\(if .tipo == "info" then "lista" else "warn" end)\">\(if .tipo == "info" then "ℹ" else "⚠" end) \(.pr | e): \(.msg | codigo)</li>") | join("")) + "</ul>"
         else "" end)
      + "<h2>Arquivos mexidos</h2>"
      + (if ($m.arquivos | length) == 0
         then "<p class=\"lista\">\(if $m.analise then "Nenhum arquivo nos PRs." else "Ainda sem leitura dos PRs." end)</p>"
         else ($m.arquivos | map("<h3>\(.repo | e) <span class=\"lista\">(\(.caminhos | length)\(if .truncado then ", mais de 100 no PR: lista parcial" else "" end))</span></h3><ul>"
                 + (.caminhos | grupos | map(item_grupo) | join("")) + "</ul>") | join("")) end)
      + (if ($m.docs | length) > 0
         then "<h2>Documentos da demanda</h2><p>" + ($m.docs | map("<a href=\"\(@uri)\">\(e)</a>") | join(" · ")) + "</p>" else "" end)
      + (if ($m.historico | length) > 0
         then "<h2>Histórico</h2><ol class=\"hist\">"
              + ($m.historico | reverse | map("<li><span class=\"ts\">\(.ts | hist_quando)</span>\(.txt | e)</li>") | join("")) + "</ol>"
         else "" end);
      "");

def paginas($local; $cache; $aviso; $agora):
  [$local[] | modelo($cache)] as $ms
  | "painel.html\u0000" + indice($ms; $aviso; $agora) + "\u0000",
    ($ms[] | "\(.slug)/resumo.html\u0000" + detalhe($agora) + "\u0000");
