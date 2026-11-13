# Fixtures da fila do flow (`flow-queue.mjs --resumo`, recorte do formato do plugin 0.39.2):
# {"<repo>": saída do --resumo}. Uso: jq -n -f tests/fixtures/fila.jq
def it($b; $h; $p; $st; $label; $acao; $cmd; $papel): {branch: $b, titulo: $b, hml: $h, prod: $p, review: $h,
  autor: "mariomendonca-1beat", state: $st, label: $label, comando: $cmd, acao: $acao, rotulo: $label,
  rodadas: 0, vez: {papel: $papel, sua: ($papel == "autor"), texto: "a vez de \($papel)"}, desde: "2026-11-12T12:00:00Z",
  parada: "1d", urls: {}, migracao_manual: false, alerta: false, origem: "aberto", conjunto: null,
  espera: {em_espera: false, segura: 0, raizes: []}};
def resumo($repo; $itens): {viewer: "mariomendonca-1beat", repo: "onebeatco/\($repo)", now: "2026-11-13T18:00:00Z",
  total: ($itens | length), suasComOutros: $itens, mesa: {revisar: [], publicarHml: [], publicarProd: []}, avisos: []};
{
  "jaguar-plus": resumo("jaguar-plus"; [
    it("prio"; 200; 201; "4a"; "aguardando o review do revisor"; "revisar"; "pr-review"; "revisor"),
    it("val-plus"; 212; 213; "6b"; "validado em homolog, aguardando liberação de produção"; "publicar_prod"; "avisar o revisor para merjar o PR de PROD"; "revisor"),
    it("stg-plus"; 220; 221; "4a"; "aguardando o review do revisor"; "revisar"; "pr-review"; "revisor"),
    (it("dep"; 240; 241; "7b"; "merjado em produção, falta aplicar"; "publicar_prod"; "/deploy production"; "revisor") | .origem = "merjado")
  ]),
  "jaguar-beta": resumo("jaguar-beta"; [
    (it("prio-b"; 300; 301; "5"; "revisado e aprovado, aguardando o revisor merjar o PR de HML"; "publicar_hml"; "aguardar o merge do PR de HML pelo revisor"; "revisor")
      | .rotulo = "aprovado"
      | .espera = {em_espera: true, segura: 0, ambiente: "HML", raizes: [{tipo: "pr", repo: "onebeatco/jaguar-plus", numero: 200}],
                   cobranca: {papel: "autor", login: "mariomendonca-1beat"}}),
    it("val-b"; 310; 311; "6b"; "validado em homolog, aguardando liberação de produção"; "publicar_prod"; "avisar o revisor para merjar o PR de PROD"; "revisor"),
    (it("stg-b"; 320; 321; "5"; "revisado e aprovado, aguardando o revisor merjar o PR de HML"; "publicar_hml"; "aguardar o merge do PR de HML pelo revisor"; "revisor") | .rotulo = "aprovado"),
    (it("desat"; 330; 331; "5"; "revisado e aprovado, aguardando o revisor merjar o PR de HML"; "publicar_hml"; "aguardar o merge do PR de HML pelo revisor"; "revisor") | .warnings = ["aprovado_desatualizado"]),
    (it("desat2"; 340; 341; "5"; "revisado e aprovado, aguardando o revisor merjar o PR de HML"; "publicar_hml"; "aguardar o merge do PR de HML pelo revisor"; "revisor") | .warnings = ["aprovado_desatualizado"])
  ]),
  "jaguar-plus-frontend": resumo("jaguar-plus-frontend"; [
    (it("revert"; 400; null; "2"; "trabalho pronto, sem PR"; "abrir_par"; "pr-open --restage"; "autor") | .review = 400),
    it("bull"; 401; 405; "6"; "em homolog, aguardando validação"; "validar"; "flow validado"; "autor"),
    it("tudo"; 402; 406; "4a"; "aguardando o review do revisor"; "revisar"; "pr-review"; "revisor"),
    it("muitos"; 403; 407; "4a"; "aguardando o review do revisor"; "revisar"; "pr-review"; "revisor")
  ])
}
