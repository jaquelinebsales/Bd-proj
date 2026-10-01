"""
Gera documentacao/cobertura_anp.html a partir de dados/cobertura/cobertura.json,
do resultado do experimento de janela de treino e de scripts/anp/cobertura_template.html.

Uso: python scripts/anp/gerar_mockup_cobertura.py
(rodar antes: scripts/anp/analise_cobertura.py e scripts/ml/experimento_janela_treino.py)
"""
import json
from datetime import date
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
cob = json.loads((RAIZ / "dados" / "cobertura" / "cobertura.json").read_text(encoding="utf-8"))
exp = json.loads((RAIZ / "dados" / "ml" / "experimento_janela_treino.json").read_text(encoding="utf-8"))


def mae(teste, h, cenario):
    for r in exp:
        if r["teste"] == teste and r["horizonte_semanas"] == h and r["cenario"] == cenario:
            return r["modelo"]["mae_reais"]


geo = cob["geo"]
municipios = [[m["c"], m["n"], m["u"], m["p"], m["q"], 1 if m["k"] else 0, round(m["d"], 1), m["g"]]
              for m in geo["municipios"]]

# Exemplo do celular: o município sem coleta com mais postos no Amazonas.
ufs = {u["uf"]: u for u in cob["ufs"]}
cand = [m for m in geo["municipios"] if m["u"] == "AM" and not m["k"] and m["p"] > 0]
ex = max(cand, key=lambda m: m["p"])
exemplo = {"nome": ex["n"], "uf": ex["u"], "postos": ex["p"], "dist": ex["d"],
           "margem": ufs["AM"]["erro_estimativa_vizinho"]}

dados = {
    "total": cob["total"],
    "regioes": cob["regioes"],
    "ufs": [{k: v for k, v in u.items()} for u in cob["ufs"]],
    "erro_por_distancia": cob["erro_por_distancia"],
    "serie_mensal": cob["serie_mensal"],
    "m": municipios,
    "u": geo["ufs"],
    "exp": {"h1_2anos": mae("2026-1", 1, "2_anos"), "h1_ingenuo": mae("2026-1", 1, "ingenuo_repete_preco"),
            "h4_2anos": mae("2026-1", 4, "2_anos"), "h4_ingenuo": mae("2026-1", 4, "ingenuo_repete_preco")},
    "exemplo": exemplo,
    "gerado_em": date.today().strftime("%d/%m/%Y"),
}
tpl = (RAIZ / "scripts" / "anp" / "cobertura_template.html").read_text(encoding="utf-8")
html = tpl.replace("/*DATA*/null", json.dumps(dados, ensure_ascii=False, separators=(",", ":")).replace("NaN", "null"))
saida = RAIZ / "documentacao" / "cobertura_anp.html"
saida.write_text(html, encoding="utf-8")
print(saida, f"{saida.stat().st_size / 1e6:.1f} MB", "exemplo:", exemplo)
