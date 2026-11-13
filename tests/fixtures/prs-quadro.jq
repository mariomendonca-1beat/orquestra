# Fixtures GraphQL dos testes do quadro (mesmo formato de prs.jq). $SHA330/$SHA340: o sha aprovado
# (o run.sh troca os marcadores __SHA330__/__SHA340__ depois de montar o repo git do patch-id).
def ev($t; $at): {createdAt: $at, author: {login: "igormeloonebeat", __typename: "User"},
  body: "<!-- flow:event {\"type\":\"\($t)\",\"at\":\"\($at)\",\"actor\":\"igormeloonebeat\"} -->"};
def pr($n; $base; $state; $mergedAt; $mss; $files; $comments): {
  number: $n, title: "PR \($n)", url: "https://github.com/o/r/pull/\($n)", state: $state, isDraft: false,
  baseRefName: $base, headRefName: "feat/x", mergedAt: $mergedAt,
  mergedBy: (if $mergedAt then {login: "igormeloonebeat"} else null end), closedAt: null,
  mergeable: (if $state != "OPEN" then "UNKNOWN" elif $mss == "DIRTY" then "CONFLICTING" else "MERGEABLE" end),
  mergeStateStatus: (if $state != "OPEN" then "UNKNOWN" else $mss end), author: {login: "mariomendonca-1beat"},
  files: {totalCount: ($files | length), nodes: ($files | map({path: .}))},
  comments: {totalCount: ($comments | length), nodes: $comments}, reviews: {nodes: []} };
def t($d): "2026-11-\($d)T12:00:00Z";
def dois: {createdAt: t(23), author: {login: "igormeloonebeat", __typename: "User"},
  body: "Aplicado.\n<!-- flow:event {\"type\":\"deploy_hml\",\"at\":\"2026-11-10T19:33:36Z\",\"actor\":\"igormeloonebeat\"} -->\n<!-- flow:event {\"type\":\"deploy_prod\",\"at\":\"2026-11-10T19:33:36Z\",\"actor\":\"igormeloonebeat\"} -->\n<!-- flow:event {quebrado} -->"};
def aprov($sha): {createdAt: t(11), author: {login: "guilhermesjlender-1beat", __typename: "User"},
  body: "<!-- flow:event {\"type\":\"aprovado\",\"at\":\"2026-11-11T12:00:00Z\",\"actor\":\"guilhermesjlender-1beat\",\"note\":\"medido contra staging × \($sha)\"} -->"};
{
  "jaguar-plus": {
    "200": pr(200; "staging"; "OPEN"; null; "BLOCKED"; ["db/a.sql"]; []),
    "201": pr(201; "production"; "OPEN"; null; "BLOCKED"; ["db/a.sql"]; []),
    "212": pr(212; "staging"; "MERGED"; "2026-11-09T12:00:00Z"; null; []; []),
    "213": pr(213; "production"; "OPEN"; null; "BLOCKED"; []; []),
    "220": pr(220; "staging"; "OPEN"; null; "BLOCKED"; []; []),
    "221": pr(221; "production"; "OPEN"; null; "BLOCKED"; []; []),
    "230": pr(230; "staging"; "MERGED"; "2026-11-09T12:00:00Z"; null; ["db/z.sql"]; [ev("deploy_hml"; t(9) | sub("12:"; "13:"))]),
    "231": pr(231; "production"; "MERGED"; "2026-11-10T17:53:57Z"; null; ["db/z.sql"]; [dois]),
    "240": pr(240; "staging"; "MERGED"; "2026-11-09T12:00:00Z"; null; []; []),
    "241": pr(241; "production"; "MERGED"; "2026-11-10T12:00:00Z"; null; ["db/w.sql"]; [])
  },
  "jaguar-beta": {
    "300": pr(300; "staging"; "OPEN"; null; "BLOCKED"; []; []),
    "301": pr(301; "master"; "OPEN"; null; "BLOCKED"; []; []),
    "310": pr(310; "staging"; "MERGED"; "2026-11-09T12:00:00Z"; null; []; []),
    "311": pr(311; "master"; "OPEN"; null; "DIRTY"; []; []),
    "320": pr(320; "staging"; "OPEN"; null; "DIRTY"; []; []),
    "321": pr(321; "master"; "OPEN"; null; "BLOCKED"; []; []),
    "330": pr(330; "staging"; "OPEN"; null; "BLOCKED"; []; [aprov("__SHA330__")]),
    "331": pr(331; "master"; "OPEN"; null; "BLOCKED"; []; []),
    "340": pr(340; "staging"; "OPEN"; null; "BLOCKED"; []; [aprov("__SHA340__")]),
    "341": pr(341; "master"; "OPEN"; null; "BLOCKED"; []; [])
  },
  "jaguar-plus-frontend": {
    "400": pr(400; "staging"; "OPEN"; null; "BLOCKED"; ["admin/src/a.ts", "api/src/b.ts"]; []),
    "401": pr(401; "staging"; "MERGED"; "2026-11-09T12:00:00Z"; null; ["bull/src/x.ts"]; []),
    "405": pr(405; "master"; "OPEN"; null; "BLOCKED"; ["bull/src/x.ts"]; []),
    "402": pr(402; "staging"; "OPEN"; null; "BLOCKED"; ["bull/a", "api/b", "frontend/c", "admin/d"]; []),
    "406": pr(406; "master"; "OPEN"; null; "BLOCKED"; []; []),
    "403": (pr(403; "staging"; "OPEN"; null; "BLOCKED"; ["bull/a"]; []) | .files.totalCount = 150),
    "407": pr(407; "master"; "OPEN"; null; "BLOCKED"; []; [])
  }
}
