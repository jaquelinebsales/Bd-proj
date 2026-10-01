"""
Experimento: quanto histórico da ANP o modelo de previsão precisa?

Compara o erro da previsão do preço semanal (mediana por município e combustível)
treinando com janelas diferentes de histórico:
    completo  todos os dados desde 2020
    4_anos    só os 4 anos anteriores ao início do teste
    2_anos    só os 2 anos anteriores ao início do teste (o que cabe no banco do Supabase gratuito)

Cada cenário só "enxerga" os dados da sua janela, inclusive para calcular as
variáveis de entrada (atrasos, médias nacionais etc.), simulando a situação real.

Testes (validação fora da amostra, sem vazamento de futuro):
    2025-2  treino com alvos até 30/06/2025, teste com alvos de jul a dez/2025
    2026-1  treino com alvos até 31/12/2025, teste com alvos de jan a jun/2026
Horizontes: 1 semana e 4 semanas à frente.

Entrada : dados/anp_limpo/precos_anp.csv (ou precos_anp_historico.csv.gz) e postos.csv
Saída   : dados/ml/experimento_janela_treino.json
Requer  : pandas, numpy, scikit-learn
Uso     : python scripts/ml/experimento_janela_treino.py
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingRegressor

RAIZ = Path(__file__).resolve().parents[2]
LIMPO = RAIZ / "dados" / "anp_limpo"
SAIDA = RAIZ / "dados" / "ml"

HORIZONTES = [1, 4]
FOLDS = {"2025-2": ("2025-07-01", "2025-12-31"), "2026-1": ("2026-01-01", "2026-06-30")}
JANELAS = {"completo": None, "4_anos": 4, "2_anos": 2}
LAGS = [1, 2, 4, 8, 13, 26, 52]
SEMENTE = 42


def carregar_semanal() -> pd.DataFrame:
    arq = LIMPO / "precos_anp.csv"
    if not arq.exists():
        arq = LIMPO / "precos_anp_historico.csv.gz"
    p = pd.read_csv(arq, parse_dates=["data_coleta"])
    p = p[p["anomalia"].astype(str).str.lower() != "true"]          # anomalias fora do cálculo
    postos = pd.read_csv(LIMPO / "postos.csv", usecols=["id", "municipio", "uf"], dtype={"municipio": str, "uf": str})
    p = p.merge(postos, left_on="posto_id", right_on="id")
    p["semana"] = p["data_coleta"].dt.to_period("W-SUN").dt.start_time
    s = (p.groupby(["uf", "municipio", "produto_id", "semana"])
           .agg(preco=("preco", "median"), n_postos=("posto_id", "nunique"))
           .reset_index())
    s["serie"] = s["uf"] + "|" + s["municipio"] + "|" + s["produto_id"].astype(str)
    return s


def montar_variaveis(s: pd.DataFrame) -> pd.DataFrame:
    """Recebe o semanal já cortado na janela do cenário e devolve uma grade semanal com variáveis."""
    semanas = pd.date_range(s["semana"].min(), s["semana"].max(), freq="W-MON")
    s = s.copy()
    s["lp"] = np.log(s["preco"])

    # Referências de mercado calculadas só com os dados da janela.
    nac = s.groupby(["produto_id", "semana"])["lp"].median().rename("lp_nac").reset_index()
    uf = s.groupby(["uf", "produto_id", "semana"])["lp"].median().rename("lp_uf").reset_index()

    info = s.drop_duplicates("serie").set_index("serie")[["uf", "municipio", "produto_id"]]
    grade = pd.MultiIndex.from_product([info.index, semanas], names=["serie", "semana"])
    g = (s.set_index(["serie", "semana"])[["lp", "n_postos"]].reindex(grade).reset_index())
    g = g.join(info, on="serie")
    g = g.merge(nac, on=["produto_id", "semana"], how="left").merge(uf, on=["uf", "produto_id", "semana"], how="left")
    g = g.sort_values(["serie", "semana"]).reset_index(drop=True)

    grp = g.groupby("serie", sort=False)
    for k in LAGS:
        g[f"r{k}"] = g["lp"] - grp["lp"].shift(k)
    # Variação da mediana nacional e estadual do mesmo combustível.
    for k in (1, 4, 13):
        g[f"nac_r{k}"] = g["lp_nac"] - grp["lp_nac"].shift(k)
        g[f"uf_r{k}"] = g["lp_uf"] - grp["lp_uf"].shift(k)
    g["rel_uf"] = g["lp"] - g["lp_uf"]
    g["rel_nac"] = g["lp"] - g["lp_nac"]
    g["obs_13"] = grp["lp"].transform(lambda x: x.notna().rolling(13, min_periods=1).sum())
    g["semana_ano"] = g["semana"].dt.isocalendar().week.astype(int)
    g["uf_cod"] = g["uf"].astype("category").cat.codes
    for h in HORIZONTES:
        g[f"y{h}"] = grp["lp"].shift(-h) - g["lp"]
        g[f"alvo_semana{h}"] = grp["semana"].shift(-h)
    return g


VARIAVEIS = ([f"r{k}" for k in LAGS]
             + [f"nac_r{k}" for k in (1, 4, 13)] + [f"uf_r{k}" for k in (1, 4, 13)]
             + ["rel_uf", "rel_nac", "obs_13", "semana_ano", "produto_id", "uf_cod", "n_postos"])
CATEGORICAS = ["produto_id", "uf_cod"]


def metricas(real: np.ndarray, prev: np.ndarray, atual: np.ndarray) -> dict:
    erro = np.abs(prev - real)
    mudou = np.abs(real - atual) / atual >= 0.01
    return {
        "mae_reais": float(erro.mean()),
        "mape_pct": float((erro / real).mean() * 100),
        "rmse_reais": float(np.sqrt(((prev - real) ** 2).mean())),
        "mae_quando_preco_mudou_1pct": float(erro[mudou].mean()) if mudou.any() else None,
        "casos": int(len(real)),
        "casos_preco_mudou_1pct": int(mudou.sum()),
    }


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    semanal = carregar_semanal()
    print(f"séries: {semanal['serie'].nunique()}  pontos semanais: {len(semanal)}", flush=True)
    resultados = []

    for fold, (ini, fim) in FOLDS.items():
        ini, fim = pd.Timestamp(ini), pd.Timestamp(fim)
        por_cenario = {}
        for nome, anos in JANELAS.items():
            inicio_janela = semanal["semana"].min() if anos is None else ini - pd.DateOffset(years=anos)
            s = semanal[(semanal["semana"] >= inicio_janela) & (semanal["semana"] <= fim)]
            g = montar_variaveis(s)
            for h in HORIZONTES:
                y, alvo = f"y{h}", f"alvo_semana{h}"
                base = g[g["lp"].notna() & g[y].notna()]
                treino = base[base[alvo] < ini]
                teste = base[(base[alvo] >= ini) & (base[alvo] <= fim)]
                modelo = HistGradientBoostingRegressor(
                    loss="absolute_error", learning_rate=0.05, max_iter=400, max_leaf_nodes=31,
                    min_samples_leaf=50, l2_regularization=1.0, categorical_features=CATEGORICAS,
                    early_stopping=True, validation_fraction=0.1, random_state=SEMENTE)
                modelo.fit(treino[VARIAVEIS], treino[y])
                t = teste[["serie", "semana", "lp", y]].copy()
                t["prev_y"] = modelo.predict(teste[VARIAVEIS])
                por_cenario[(nome, h)] = (t, len(treino), treino["semana"].min())
                print(f"{fold} {nome:9s} h={h}: treino={len(treino):>7} teste={len(teste):>6}", flush=True)

        # Avalia todos os cenários nos casos de teste em comum (interseção), por horizonte.
        for h in HORIZONTES:
            comuns = None
            for nome in JANELAS:
                t = por_cenario[(nome, h)][0]
                k = set(zip(t["serie"], t["semana"]))
                comuns = k if comuns is None else comuns & k
            for nome in JANELAS:
                t, n_treino, desde = por_cenario[(nome, h)]
                t = t[[x in comuns for x in zip(t["serie"], t["semana"])]]
                atual = np.exp(t["lp"].to_numpy())
                real = atual * np.exp(t[f"y{h}"].to_numpy())
                prev = atual * np.exp(t["prev_y"].to_numpy())
                r = {"teste": fold, "horizonte_semanas": h, "cenario": nome,
                     "treino_desde": str(desde.date()), "linhas_treino": n_treino,
                     "modelo": metricas(real, prev, atual)}
                if nome == "completo":
                    resultados.append({"teste": fold, "horizonte_semanas": h, "cenario": "ingenuo_repete_preco",
                                       "treino_desde": None, "linhas_treino": 0,
                                       "modelo": metricas(real, atual, atual)})
                resultados.append(r)
                # Erro por combustível
                prod = t["serie"].str.split("|").str[2].astype(int).to_numpy()
                r["por_produto_mae"] = {int(p): float(np.abs(prev - real)[prod == p].mean()) for p in np.unique(prod)}
                ufs = t["serie"].str.split("|").str[0].to_numpy()
                r["por_uf"] = {u: {"mae_reais": float(np.abs(prev - real)[ufs == u].mean()),
                                   "mae_ingenuo": float(np.abs(atual - real)[ufs == u].mean()),
                                   "casos": int((ufs == u).sum())} for u in np.unique(ufs)}

    (SAIDA / "experimento_janela_treino.json").write_text(json.dumps(resultados, indent=2, ensure_ascii=False), encoding="utf-8")
    print("\nteste   h  cenario               desde        MAE(R$)  MAPE%   MAE quando mudou>=1%")
    for r in resultados:
        m = r["modelo"]
        print(f"{r['teste']}  {r['horizonte_semanas']}  {r['cenario']:20s}  {str(r['treino_desde']):10s}  "
              f"{m['mae_reais']:.4f}  {m['mape_pct']:.3f}  {m['mae_quando_preco_mudou_1pct']:.4f}  (n={m['casos']})")


if __name__ == "__main__":
    main()
