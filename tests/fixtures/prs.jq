# Fixtures do `orq prs`: {"<repo>": {"<n>": nó do PR}}, no formato do GraphQL do GitHub.
# Uso: jq -n -f tests/fixtures/prs.jq   (o run.sh grava um arquivo por repo)
def ev($t; $at): {createdAt: $at, author: {login: "rev", __typename: "User"},
  body: "<!-- flow:event {\"type\":\"\($t)\",\"at\":\"\($at)\",\"actor\":\"rev\"} -->\nlinha legível"};
def pr($n; $base; $state; $mergedAt; $mss; $files; $comments): {
  number: $n, title: "PR \($n)", url: "https://github.com/o/r/pull/\($n)", state: $state, isDraft: false,
  baseRefName: $base, headRefName: "feat/x", mergedAt: $mergedAt,
  mergedBy: (if $mergedAt then {login: "rev"} else null end), closedAt: null,
  mergeable: (if $state != "OPEN" then "UNKNOWN" elif $mss == "DIRTY" then "CONFLICTING"
              elif $mss == "UNKNOWN" then "UNKNOWN" else "MERGEABLE" end),
  mergeStateStatus: (if $state != "OPEN" then "UNKNOWN" else $mss end), author: {login: "autor"},
  files: {totalCount: ($files | length), nodes: ($files | map({path: .}))},
  comments: {totalCount: ($comments | length), nodes: $comments} };
def t($d): "2026-10-\($d)T12:00:00Z";
def bot: {createdAt: t(25), author: {login: "github-actions", __typename: "Bot"},
  body: "<!-- flow:event {\"type\":\"validado\",\"at\":\"2026-10-25T12:00:00Z\"} -->"};

{
  "jaguar-beta": {
    "10": pr(10; "staging"; "MERGED"; t(20); null; []; [ev("aprovado"; t(19))]),
    "11": pr(11; "master"; "OPEN"; null; "DIRTY"; []; [ev("validado"; t(21))]),
    "40": pr(40; "staging"; "MERGED"; t(20); null; []; []),
    "42": pr(42; "develop"; "OPEN"; null; "CLEAN"; []; []),
    "41": pr(41; "master"; "OPEN"; null; "CLEAN"; []; [ev("validado"; t(19)), bot]),
    "50": pr(50; "staging"; "MERGED"; t(20); null; []; []),
    "51": (pr(51; "master"; "OPEN"; null; "UNKNOWN"; []; [ev("validado"; t(22))])
           + {_leve: [{mergeable: "MERGEABLE", mergeStateStatus: "BLOCKED"}]}),
    "60": (pr(60; "staging"; "OPEN"; null; "UNKNOWN"; []; [])
           + {_leve: [{mergeable: "UNKNOWN", mergeStateStatus: "UNKNOWN"}]}),
    "80": pr(80; "staging"; "MERGED"; t(10); null; []; []),
    "90": pr(90; "staging"; "MERGED"; t(20); null; []; []),
    "91": pr(91; "master"; "MERGED"; t(22); null; []; [ev("validado"; t(21))])
  },
  "jaguar-plus": {
    "20": pr(20; "staging"; "MERGED"; t(20); null; ["db/a.sql"]; [ev("deploy_hml"; t(21))]),
    "21": pr(21; "production"; "MERGED"; t(19); null; ["db/a.sql"]; [ev("deploy_prod"; t(21))]),
    "22": pr(22; "production"; "MERGED"; t(19); null; []; []),
    "23": pr(23; "staging"; "OPEN"; null; "BLOCKED"; []; []),
    "30": pr(30; "staging"; "MERGED"; t(20); null; ["db/fn/x.sql", "README.md"]; [ev("deploy_hml"; t(19))]),
    "31": pr(31; "production"; "OPEN"; null; "BLOCKED"; ["db/fn/x.sql"]; []),
    "32": pr(32; "staging"; "MERGED"; t(20); null; ["y.sql"]; [ev("deploy_hml"; t(21)), ev("validado"; t(22))]),
    "33": pr(33; "production"; "MERGED"; t(23); null; ["y.sql"]; [ev("deploy_prod"; t(22))])
  },
  "outro": {
    "70": pr(70; "main"; "OPEN"; null; "CLEAN"; []; [])
  }
}
