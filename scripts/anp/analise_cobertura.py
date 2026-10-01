"""
Cobertura geográfica da pesquisa de preços da ANP.

Cruza o cadastro completo de postos autorizados (ANP) com os postos que aparecem
na pesquisa de preços dos últimos 12 meses e mede:
  - quantos postos e municípios a pesquisa cobre, por UF e por região;
  - a distância de cada município sem pesquisa até o município pesquisado mais próximo;
  - o erro de estimar o preço de um município usando só vizinhos (simulação de
    município não coberto), por UF e por faixa de distância.

Entrada:
  dados/anp_limpo/precos_anp.csv, postos.csv
  dados/externos/anp_cadastro_revendedores.csv    (cadastro oficial ANP)
  dados/externos/ibge_municipios.geojson           (malha municipal IBGE, qualidade mínima)
  dados/externos/ibge_ufs.geojson                  (malha estadual IBGE)
  dados/externos/ibge_municipios_lista.json        (nomes e UFs dos municípios)
  dados/ml/experimento_janela_treino.json          (opcional, erro do modelo por UF)
Saída:
  dados/cobertura/cobertura.json

Requer pandas e numpy.
"""
from __future__ import annotations

import json
import math
import unicodedata
from pathlib import Path

import numpy as np
import pandas as pd

RAIZ = Path(__file__).resolve().parents[2]
LIMPO = RAIZ / "dados" / "anp_limpo"
EXT = RAIZ / "dados" / "externos"
SAIDA = RAIZ / "dados" / "cobertura"
INICIO_JANELA = pd.Timestamp("2025-07-01")   # últimos 12 meses de pesquisa disponíveis
PRODUTO_REF = 1                              # gasolina comum

REGIAO = {**dict.fromkeys(["AC", "AP", "AM", "PA", "RO", "RR", "TO"], "Norte"),
          **dict.fromkeys(["AL", "BA", "CE", "MA", "PB", "PE", "PI", "RN", "SE"], "Nordeste"),
          **dict.fromkeys(["DF", "GO", "MT", "MS"], "Centro-Oeste"),
          **dict.fromkeys(["ES", "MG", "RJ", "SP"], "Sudeste"),
          **dict.fromkeys(["PR", "RS", "SC"], "Sul")}


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode()
    s = s.upper().replace("-", " ").replace("'", " ").replace("`", " ")
    return " ".join(s.split())


# Grafias que diferem entre ANP e IBGE (acrescentar aqui quando aparecerem novas).
APELIDOS = {
    ("SP", "MOJI MIRIM"): "MOGI MIRIM", ("SP", "MOJI DAS CRUZES"): "MOGI DAS CRUZES",
    ("SP", "MOJI GUACU"): "MOGI GUACU", ("RN", "ACU"): "ASSU", ("RN", "AUGUSTO SEVERO"): "CAMPO GRANDE",
    ("RN", "BOA SAUDE"): "JANUARIO CICCO", ("GO", "BOM JESUS"): "BOM JESUS DE GOIAS",
    ("RR", "SAO LUIZ"): "SAO LUIZ DO ANAUA", ("TO", "FORTALEZA DO TABOCAO"): "TABOCAO",
    ("PB", "SANTAREM"): "JOCA CLAUDINO", ("MG", "SAO THOME DAS LETRAS"): "SAO TOME DAS LETRAS",
    ("PE", "BELEM DE SAO FRANCISCO"): "BELEM DO SAO FRANCISCO", ("TO", "SAO VALERIO DA NATIVIDADE"): "SAO VALERIO",
    ("BA", "SANTA TERESINHA"): "SANTA TEREZINHA", ("MT", "POXOREO"): "POXOREU",
    ("SC", "PICARRAS"): "BALNEARIO PICARRAS", ("SC", "PRESIDENTE CASTELO BRANCO"): "PRESIDENTE CASTELLO BRANCO",
    ("RS", "SANTANA DO LIVRAMENTO"): "SANT ANA DO LIVRAMENTO",
}


def uf_do_municipio(m: dict) -> str:
    try:
        return m["microrregiao"]["mesorregiao"]["UF"]["sigla"]
    except (TypeError, KeyError):
        return m["regiao-imediata"]["regiao-intermediaria"]["UF"]["sigla"]


def centroide(geom: dict) -> tuple[float, float]:
    """Centroide ponderado por área (lon, lat) do maior anel externo."""
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    melhor, area_max = None, -1.0
    for poly in polys:
        anel = poly[0]
        a = cx = cy = 0.0
        for (x0, y0), (x1, y1) in zip(anel, anel[1:]):
            f = x0 * y1 - x1 * y0
            a += f; cx += (x0 + x1) * f; cy += (y0 + y1) * f
        if abs(a) > area_max:
            area_max = abs(a)
            melhor = (cx / (3 * a), cy / (3 * a)) if a else tuple(np.mean(anel, axis=0))
    return melhor


def km(lon1, lat1, lon2, lat2):
    r = 6371.0
    p1, p2 = np.radians(lat1), np.radians(lat2)
    dp, dl = p2 - p1, np.radians(lon2 - lon1)
    a = np.sin(dp / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * r * np.arcsin(np.sqrt(a))


# ---------- projeção e simplificação para o SVG do mockup ----------
LAT0 = math.radians(-15)
ESCALA = 26.0   # unidades SVG por grau


def proj(lon, lat):
    return ((lon + 74.5) * ESCALA * math.cos(LAT0), (6.0 - lat) * ESCALA)


def caminho_svg(geom: dict, passo: float) -> str:
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    partes = []
    for poly in polys:
        for anel in poly:
            pts, ult = [], None
            for lon, lat in anel:
                x, y = proj(lon, lat)
                q = (round(x / passo) * passo, round(y / passo) * passo)
                if q != ult:
                    pts.append(q); ult = q
            if len(pts) >= 4:
                partes.append("M" + "L".join(f"{x:g},{y:g}" for x, y in pts) + "Z")
    return "".join(partes)


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)

    # ---------- municípios IBGE ----------
    lista = json.loads((EXT / "ibge_municipios_lista.json").read_text(encoding="utf-8"))
    mun = pd.DataFrame([{"cod": str(m["id"]), "nome": m["nome"], "uf": uf_do_municipio(m)} for m in lista])
    mun["chave"] = mun["uf"] + "|" + mun["nome"].map(norm)
    geo = json.loads((EXT / "ibge_municipios.geojson").read_text(encoding="utf-8"))
    cent = {f["properties"]["codarea"]: centroide(f["geometry"]) for f in geo["features"]}
    sem_malha = mun[~mun["cod"].isin(cent)][["cod", "nome", "uf"]].values.tolist()  # municípios novos
    mun = mun[mun["cod"].isin(cent)].copy()
    mun["lon"] = mun["cod"].map(lambda c: cent[c][0])
    mun["lat"] = mun["cod"].map(lambda c: cent[c][1])
    chave_cod = dict(zip(mun["chave"], mun["cod"]))
    nomes_uf = mun.groupby("uf")["chave"].apply(lambda s: [c.split("|", 1)[1] for c in s]).to_dict()
    import difflib
    aproximados = {}

    def cod(uf, nome):
        n = norm(nome)
        n = APELIDOS.get((uf, n), n)
        c = chave_cod.get(f"{uf}|{n}")
        if c is None:   # grafia diferente: busca aproximada dentro da UF
            m = difflib.get_close_matches(n, nomes_uf.get(uf, []), n=1, cutoff=0.8)
            if m:
                c = chave_cod[f"{uf}|{m[0]}"]
                aproximados[(uf, n)] = m[0]
        return c

    # ---------- cadastro completo ANP ----------
    bruto = (EXT / "anp_cadastro_revendedores.csv").read_bytes()
    try:
        txt = bruto.decode("utf-8-sig")
    except UnicodeDecodeError:
        txt = bruto.decode("cp1252")
    from io import StringIO
    cad = pd.read_csv(StringIO(txt), sep=";", dtype=str)
    cad["CNPJ"] = cad["CNPJ"].str.replace(r"\D", "", regex=True).str.zfill(14)
    cad["cod"] = [cod(u, m) for u, m in zip(cad["UF"], cad["MUNICIPIO"])]
    sem_mun_cad = cad[cad["cod"].isna()][["UF", "MUNICIPIO"]].drop_duplicates()

    # ---------- postos pesquisados nos últimos 12 meses ----------
    precos = pd.read_csv(LIMPO / "precos_anp.csv", parse_dates=["data_coleta"])
    precos = precos[precos["data_coleta"] >= INICIO_JANELA]
    postos = pd.read_csv(LIMPO / "postos.csv", dtype=str)
    postos["id"] = postos["id"].astype(int)
    postos["cod"] = [cod(u, m) for u, m in zip(postos["uf"], postos["municipio"])]
    pesq_ids = set(precos["posto_id"])
    pesq = postos[postos["id"].isin(pesq_ids)]
    sem_mun_pesq = pesq[pesq["cod"].isna()][["uf", "municipio"]].drop_duplicates()
    mun_cobertos = set(pesq["cod"].dropna())

    # ---------- por município ----------
    n_cad = cad.groupby("cod").size()
    n_pesq = pesq.groupby("cod").size()
    mun["postos"] = mun["cod"].map(n_cad).fillna(0).astype(int)
    mun["postos_pesquisados"] = mun["cod"].map(n_pesq).fillna(0).astype(int)
    mun["coberto"] = mun["cod"].isin(mun_cobertos)

    cob = mun[mun["coberto"]]
    # distância até o município coberto mais próximo (qualquer UF)
    dist = []
    for lon, lat, c in zip(mun["lon"], mun["lat"], mun["coberto"]):
        if c:
            dist.append(0.0)
        else:
            dist.append(float(km(lon, lat, cob["lon"].to_numpy(), cob["lat"].to_numpy()).min()))
    mun["dist_km"] = np.round(dist, 1)

    # ---------- simulação: estimar o preço de um município coberto usando só vizinhos ----------
    p = precos[(precos["produto_id"] == PRODUTO_REF) & (precos["anomalia"].astype(str).str.lower() != "true")]
    p = p.merge(postos[["id", "cod", "uf"]], left_on="posto_id", right_on="id").dropna(subset=["cod"])
    ref = p.groupby(["cod", "uf"])["preco"].median().reset_index()      # mediana 12 meses por município
    ref = ref.merge(mun[["cod", "lon", "lat"]], on="cod")
    sim = []
    for i, r in ref.iterrows():
        outros = ref[ref["cod"] != r["cod"]]
        d = km(r["lon"], r["lat"], outros["lon"].to_numpy(), outros["lat"].to_numpy())
        viz = int(np.argmin(d))
        mesma_uf = outros[outros["uf"] == r["uf"]]
        sim.append({
            "cod": r["cod"], "uf": r["uf"], "preco": r["preco"],
            "dist_vizinho_km": float(d[viz]),
            "erro_vizinho": abs(float(outros.iloc[viz]["preco"]) - r["preco"]),
            "erro_mediana_uf": abs(float(mesma_uf["preco"].median()) - r["preco"]) if len(mesma_uf) else np.nan,
        })
    sim = pd.DataFrame(sim)
    faixas = [0, 25, 50, 100, 200, 400, 10000]
    rot = ["até 25 km", "25–50 km", "50–100 km", "100–200 km", "200–400 km", "mais de 400 km"]
    sim["faixa"] = pd.cut(sim["dist_vizinho_km"], faixas, labels=rot, right=False)
    erro_por_dist = (sim.groupby("faixa", observed=False)
                        .agg(casos=("erro_vizinho", "size"), mae=("erro_vizinho", "mean"),
                             p90=("erro_vizinho", lambda x: float(np.percentile(x, 90)) if len(x) else np.nan))
                        .reset_index())

    # ---------- erro do modelo por UF (experimento) ----------
    modelo_uf = {}
    exp = RAIZ / "dados" / "ml" / "experimento_janela_treino.json"
    if exp.exists():
        for r in json.loads(exp.read_text(encoding="utf-8")):
            if r["teste"] == "2026-1" and r["horizonte_semanas"] == 1 and r["cenario"] == "2_anos" and "por_uf" in r:
                modelo_uf = r["por_uf"]

    # ---------- por UF ----------
    ufs = []
    for uf, g in mun.groupby("uf"):
        com_posto = g[g["postos"] > 0]
        s = sim[sim["uf"] == uf]
        nao_cob = com_posto[~com_posto["coberto"]]
        ufs.append({
            "uf": uf, "regiao": REGIAO[uf],
            "municipios": int(len(g)),
            "municipios_com_posto": int(len(com_posto)),
            "municipios_cobertos": int(g["coberto"].sum()),
            "postos": int(g["postos"].sum()),
            "postos_pesquisados": int(g["postos_pesquisados"].sum()),
            "postos_em_municipio_coberto": int(com_posto[com_posto["coberto"]]["postos"].sum()),
            "dist_mediana_km_nao_cobertos": float(nao_cob["dist_km"].median()) if len(nao_cob) else 0.0,
            "dist_max_km_nao_cobertos": float(nao_cob["dist_km"].max()) if len(nao_cob) else 0.0,
            "erro_estimativa_vizinho": float(s["erro_vizinho"].mean()) if len(s) else None,
            "erro_estimativa_mediana_uf": float(s["erro_mediana_uf"].mean()) if len(s) else None,
            "preco_medio_gasolina": float(s["preco"].mean()) if len(s) else None,
            "modelo_mae_1sem": modelo_uf.get(uf, {}).get("mae_reais"),
            "ingenuo_mae_1sem": modelo_uf.get(uf, {}).get("mae_ingenuo"),
            "modelo_series_teste": modelo_uf.get(uf, {}).get("casos"),
        })
    ufs = pd.DataFrame(ufs)

    regioes = []
    for reg, g in ufs.groupby("regiao"):
        m = mun[mun["uf"].isin(g["uf"])]
        cp = m[m["postos"] > 0]
        regioes.append({
            "regiao": reg,
            "postos": int(g["postos"].sum()),
            "postos_pesquisados": int(g["postos_pesquisados"].sum()),
            "postos_em_municipio_coberto": int(g["postos_em_municipio_coberto"].sum()),
            "municipios_com_posto": int(g["municipios_com_posto"].sum()),
            "municipios_cobertos": int(g["municipios_cobertos"].sum()),
            "dist_mediana_km_nao_cobertos": float(cp[~cp["coberto"]]["dist_km"].median()),
        })

    # ---------- geometria para o mockup ----------
    geo_uf = json.loads((EXT / "ibge_ufs.geojson").read_text(encoding="utf-8"))
    cod_uf_sigla = {"11": "RO", "12": "AC", "13": "AM", "14": "RR", "15": "PA", "16": "AP", "17": "TO",
                    "21": "MA", "22": "PI", "23": "CE", "24": "RN", "25": "PB", "26": "PE", "27": "AL",
                    "28": "SE", "29": "BA", "31": "MG", "32": "ES", "33": "RJ", "35": "SP", "41": "PR",
                    "42": "SC", "43": "RS", "50": "MS", "51": "MT", "52": "GO", "53": "DF"}
    info = mun.set_index("cod")
    geo_mun = []
    for f in geo["features"]:
        c = f["properties"]["codarea"]
        r = info.loc[c]
        geo_mun.append({"c": c, "n": r["nome"], "u": r["uf"], "p": int(r["postos"]), "q": int(r["postos_pesquisados"]),
                        "k": bool(r["coberto"]), "d": float(r["dist_km"]), "g": caminho_svg(f["geometry"], 0.5)})
    geo_ufs = [{"u": cod_uf_sigla[f["properties"]["codarea"]], "g": caminho_svg(f["geometry"], 0.5)}
               for f in geo_uf["features"]]

    total = {
        "postos_cadastro": int(len(cad)),
        "postos_cadastro_com_municipio": int(cad["cod"].notna().sum()),
        "postos_pesquisados_12m": int(len(pesq)),
        "municipios_brasil": int(len(mun)),
        "municipios_com_posto": int((mun["postos"] > 0).sum()),
        "municipios_cobertos": int(mun["coberto"].sum()),
        "postos_em_municipio_coberto": int(mun[mun["coberto"]]["postos"].sum()),
        "sem_correspondencia_cadastro": sem_mun_cad.values.tolist(),
        "sem_correspondencia_pesquisa": sem_mun_pesq.values.tolist(),
        "municipios_sem_malha_ibge": sem_malha,
        "janela_pesquisa": f"{INICIO_JANELA.date()} a 2026-06-30",
        "simulacao_erro_vizinho_geral": float(sim["erro_vizinho"].mean()),
        "simulacao_erro_mediana_uf_geral": float(sim["erro_mediana_uf"].mean()),
        "simulacao_municipios": int(len(sim)),
    }
    # ---------- série mensal da pesquisa desde jan/2024 ----------
    todos = pd.read_csv(LIMPO / "precos_anp.csv", usecols=["posto_id", "data_coleta"], parse_dates=["data_coleta"])
    todos = todos[todos["data_coleta"] >= "2024-01-01"].merge(postos[["id", "cod"]], left_on="posto_id", right_on="id")
    todos["mes"] = todos["data_coleta"].dt.to_period("M").astype(str)
    serie_mensal = (todos.groupby("mes")
                         .agg(postos=("posto_id", "nunique"), municipios=("cod", "nunique"), coletas=("posto_id", "size"))
                         .reset_index().to_dict("records"))

    out = {"total": total, "regioes": regioes, "serie_mensal": serie_mensal, "ufs": ufs.to_dict("records"),
           "erro_por_distancia": erro_por_dist.to_dict("records"),
           "geo": {"municipios": geo_mun, "ufs": geo_ufs}}
    (SAIDA / "cobertura.json").write_text(json.dumps(out, ensure_ascii=False, default=float), encoding="utf-8")

    print(json.dumps({k: v for k, v in total.items() if not k.startswith("sem_")}, indent=2, ensure_ascii=False))
    print("correspondência aproximada:", aproximados)
    print("sem correspondência (cadastro):", len(sem_mun_cad), sem_mun_cad.values.tolist()[:20])
    print("sem correspondência (pesquisa):", len(sem_mun_pesq), sem_mun_pesq.values.tolist()[:20])
    print(pd.DataFrame(regioes).to_string())
    print(ufs[["uf", "postos", "postos_pesquisados", "municipios_com_posto", "municipios_cobertos",
               "postos_em_municipio_coberto", "dist_mediana_km_nao_cobertos", "erro_estimativa_vizinho",
               "erro_estimativa_mediana_uf", "modelo_mae_1sem", "ingenuo_mae_1sem"]].to_string())
    print(erro_por_dist.to_string())


if __name__ == "__main__":
    main()
