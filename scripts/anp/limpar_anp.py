"""
Limpeza das planilhas semestrais de preços da ANP para o projeto gasprice.

Entrada : precos_ANP/ (CSVs e ZIPs originais, que não são alterados)
Saída   : dados/anp_limpo/
    produtos.csv     catálogo dos 6 combustíveis
    postos.csv       um registro por posto (CNPJ), com os dados cadastrais mais recentes
    precos_anp.csv   um preço por posto, produto e data de coleta, com a coluna "anomalia"
    anomalias.csv    detalhes dos preços marcados como anomalia (continuam em precos_anp.csv)
    removidos.csv    cada linha removida, com arquivo, linha de origem e motivo
    relatorio.json   contagens por semestre

Preços que destoam NÃO são removidos: ficam marcados com anomalia=true para
serem tratados à parte nos cálculos. Só saem linhas vazias, ilegíveis ou repetidas.

Uso: python scripts/anp/limpar_anp.py
Somente biblioteca padrão do Python (3.10+).
"""
from __future__ import annotations

import csv
import io
import json
import re
import statistics
import zipfile
import zlib
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
ENTRADA = RAIZ / "precos_ANP"
SAIDA = RAIZ / "dados" / "anp_limpo"

# Um arquivo por semestre. ca-2026-01.zip é idêntico ao CSV de 2026.01 e é ignorado.
FONTES = [
    ("2020-1", "ca-2020-01.csv"),
    ("2020-2", "ca-2020-02.csv"),
    ("2021-1", "ca-2021-01.csv"),
    ("2021-2", "ca-2021-02.csv"),
    ("2022-1", "precos-semestrais-ca.zip"),
    ("2022-2", "ca-2022-02.zip"),
    ("2023-1", "ca-2023-01.zip"),
    ("2023-2", "ca-2023-02.zip"),
    ("2024-1", "ca-2024-01.zip"),
    ("2024-2", "ca-2024-02.zip"),
    ("2025-1", "ca-2025-01.zip"),
    ("2025-2", "ca-2025-02.zip"),
    ("2026-1", "Preços semestrais - AUTOMOTIVOS_2026.01.csv"),
]

# id, código curto, nome exibido, unidade, faixa de preço plausível (R$)
PRODUTOS = {
    "GASOLINA":           (1, "GC",  "Gasolina comum",     "L",  2.00, 15.00),
    "GASOLINA ADITIVADA": (2, "GA",  "Gasolina aditivada", "L",  2.00, 15.00),
    "ETANOL":             (3, "ET",  "Etanol",             "L",  1.50, 12.00),
    "DIESEL":             (4, "DS",  "Diesel S500",        "L",  2.00, 15.00),
    "DIESEL S10":         (5, "S10", "Diesel S10",         "L",  2.00, 15.00),
    "GNV":                (6, "GNV", "GNV",                "m3", 1.50, 12.00),
}

# Um preço é descartado como erro de digitação somente se desviar mais que
# DESVIO_MAX da mediana do produto na UF e na semana (com pelo menos MIN_AMOSTRA
# preços) E mais que DESVIO_POSTO_MAX da mediana do próprio posto no semestre.
DESVIO_MAX = 0.35
DESVIO_POSTO_MAX = 0.20
MIN_AMOSTRA = 5

ESPACOS = re.compile(r"\s+")


def texto(s: str) -> str:
    return ESPACOS.sub(" ", s).strip().upper()


def complemento(s: str) -> str:
    # Ex.: ": XXXXXXXXXXXX;"  "KM: 20;"  "LOTE: 01 E 02; QUADRA: 09; : LOTEAMENTO ITAPARICA;"
    partes = [p.strip().lstrip(":").strip() for p in s.split(";")]
    partes = [p for p in partes if p and not re.fullmatch(r"X+", p)]
    return texto(", ".join(partes))


def cnpj_valido(d: str) -> bool:
    if len(d) != 14 or d == d[0] * 14:
        return False
    def dv(base: str, pesos: list[int]) -> str:
        r = sum(int(a) * b for a, b in zip(base, pesos)) % 11
        return "0" if r < 2 else str(11 - r)
    p1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    p2 = [6] + p1
    return d[12] == dv(d[:12], p1) and d[13] == dv(d[:13], p2)


def ler_texto(caminho: Path) -> str:
    if caminho.suffix.lower() == ".zip":
        with zipfile.ZipFile(caminho) as z:
            bruto = z.read(z.namelist()[0])
    else:
        bruto = caminho.read_bytes()
    try:
        return bruto.decode("utf-8-sig")
    except UnicodeDecodeError:
        return bruto.decode("cp1252")


def limites_semestre(sem: str) -> tuple[date, date]:
    ano, s = int(sem[:4]), int(sem[-1])
    return (date(ano, 1, 1), date(ano, 6, 30)) if s == 1 else (date(ano, 7, 1), date(ano, 12, 31))


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    rel: dict = {"por_semestre": {}, "descartes": Counter()}
    postos: dict[str, dict] = {}          # cnpj -> dados mais recentes
    posto_id: dict[str, int] = {}
    total_saida = 0
    bytes_csv = 0
    gz = zlib.compressobj(9, zlib.DEFLATED, 31)
    bytes_gz = 0

    f_precos = open(SAIDA / "precos_anp.csv", "w", encoding="utf-8", newline="")
    w_precos = csv.writer(f_precos, lineterminator="\n")
    w_precos.writerow(["posto_id", "produto_id", "data_coleta", "preco", "anomalia"])
    f_anom = open(SAIDA / "anomalias.csv", "w", encoding="utf-8", newline="")
    w_anom = csv.writer(f_anom, lineterminator="\n")
    w_anom.writerow(["posto_id", "cnpj", "produto_id", "data_coleta", "preco", "uf",
                     "mediana_uf_semana", "mediana_posto_semestre", "motivos"])
    f_rem = open(SAIDA / "removidos.csv", "w", encoding="utf-8", newline="")
    w_rem = csv.writer(f_rem, lineterminator="\n")
    w_rem.writerow(["arquivo_origem", "linha_origem", "motivo", "cnpj", "produto", "data", "preco", "detalhe"])
    anom_por_motivo = Counter()

    for sem, nome in FONTES:
        ini, fim = limites_semestre(sem)
        leitor = csv.reader(io.StringIO(ler_texto(ENTRADA / nome), newline=""), delimiter=";", quotechar='"')
        next(leitor)
        desc = Counter()
        lidas = 0
        linhas = []   # (cnpj, produto_id, data, preco_milesimos, uf)

        def remover(motivo: str, c: list[str]) -> None:
            desc[motivo] += 1
            if motivo != "linha_vazia":   # linhas vazias não têm conteúdo a registrar
                w_rem.writerow([nome, leitor.line_num, motivo, c[4] if len(c) > 4 else "",
                                c[10] if len(c) > 10 else "", c[11] if len(c) > 11 else "",
                                c[12] if len(c) > 12 else "", ";".join(c)[:300]])

        for c in leitor:
            lidas += 1
            if len(c) != 16:
                remover("colunas_invalidas", c); continue
            if not any(x.strip() for x in c):
                remover("linha_vazia", c); continue
            _reg, uf, mun, revenda, cnpj, rua, num, compl, bairro, cep, prod, dt, venda, _compra, _un, bandeira = c

            prod = texto(prod)
            if prod not in PRODUTOS:
                remover("produto_desconhecido", c); continue
            pid, _, _, _, pmin, pmax = PRODUTOS[prod]

            cnpj = re.sub(r"\D", "", cnpj)
            if not cnpj_valido(cnpj):
                remover("cnpj_invalido", c); continue

            try:
                d, m, a = dt.strip().split("/")
                data = date(int(a), int(m), int(d))
            except ValueError:
                remover("data_invalida", c); continue
            if not (ini <= data <= fim):
                remover("data_fora_do_semestre", c); continue

            try:
                preco = float(venda.strip().replace(",", "."))
            except ValueError:
                remover("preco_nao_numerico", c); continue
            if not (0 < preco < 100):
                remover("preco_impossivel", c); continue

            linhas.append((cnpj, pid, data, round(preco * 1000), uf.strip().upper(),
                           not (pmin <= preco <= pmax), leitor.line_num))

            atual = postos.get(cnpj)
            if atual is None or data >= atual["ultima_coleta"]:
                cep_d = re.sub(r"\D", "", cep)
                postos[cnpj] = {
                    "razao_social": texto(revenda),
                    "bandeira": texto(bandeira),
                    "logradouro": texto(rua),
                    "numero": texto(num),
                    "complemento": complemento(compl),
                    "bairro": texto(bairro),
                    "municipio": texto(mun),
                    "uf": uf.strip().upper(),
                    "cep": cep_d if len(cep_d) == 8 else "",
                    "primeira_coleta": atual["primeira_coleta"] if atual else data,
                    "ultima_coleta": data,
                }
            elif data < atual["primeira_coleta"]:
                atual["primeira_coleta"] = data

        # Deduplicação: um preço por (posto, produto, data). Fica a primeira ocorrência;
        # as demais vão para removidos.csv.
        unicos: dict[tuple, tuple] = {}
        divergentes: set[tuple] = set()
        for cnpj, pid, data, p, uf, fora_faixa, lnum in linhas:
            k = (cnpj, pid, data)
            if k in unicos:
                igual = unicos[k][0] == p
                motivo = "duplicado_identico" if igual else "duplicado_preco_divergente"
                desc[motivo] += 1
                if not igual:
                    divergentes.add(k)
                w_rem.writerow([nome, lnum, motivo, cnpj, pid, data.isoformat(), f"{p / 1000:.3f}",
                                f"mantido {unicos[k][0] / 1000:.3f}"])
                continue
            unicos[k] = (p, uf, fora_faixa)

        # Anomalias: os preços ficam na base, marcados, para serem tratados à parte nos cálculos.
        grupos = defaultdict(list)
        por_posto = defaultdict(list)
        for (cnpj, pid, data), (p, uf, _f) in unicos.items():
            grupos[(uf, pid, data.isocalendar()[:2])].append(p)
            por_posto[(cnpj, pid)].append(p)
        medianas = {k: statistics.median(v) for k, v in grupos.items() if len(v) >= MIN_AMOSTRA}
        med_posto = {k: statistics.median(v) for k, v in por_posto.items()}

        n_anom = 0
        for (cnpj, pid, data), (p, uf, fora_faixa) in sorted(unicos.items()):
            if cnpj not in posto_id:
                posto_id[cnpj] = len(posto_id) + 1
            med = medianas.get((uf, pid, data.isocalendar()[:2]))
            mp = med_posto[(cnpj, pid)]
            motivos = []
            if fora_faixa:
                motivos.append("fora_da_faixa_plausivel")
            if (med is not None and abs(p - med) / med > DESVIO_MAX
                    and abs(p - mp) / mp > DESVIO_POSTO_MAX):
                motivos.append("destoa_da_uf_e_do_proprio_posto")
            if (cnpj, pid, data) in divergentes:
                motivos.append("duplicado_com_preco_divergente")
            if motivos:
                n_anom += 1
                for mot in motivos:
                    anom_por_motivo[mot] += 1
                w_anom.writerow([posto_id[cnpj], cnpj, pid, data.isoformat(), f"{p / 1000:.3f}", uf,
                                 f"{med / 1000:.3f}" if med is not None else "", f"{mp / 1000:.3f}",
                                 "|".join(motivos)])
            linha = [posto_id[cnpj], pid, data.isoformat(), f"{p / 1000:.3f}", "true" if motivos else "false"]
            w_precos.writerow(linha)
            s = (",".join(map(str, linha)) + "\n").encode()
            bytes_csv += len(s)
            bytes_gz += len(gz.compress(s))

        rel["por_semestre"][sem] = {
            "arquivo": nome,
            "linhas_lidas": lidas,
            "precos_mantidos": len(unicos),
            "precos_anomalos": n_anom,
            "postos_no_semestre": len({k[0] for k in unicos}),
            "removidos": dict(desc),
        }
        rel["descartes"].update(desc)
        total_saida += len(unicos)
        print(f"{sem}: lidas={lidas:>7} mantidas={len(unicos):>7} descartes={dict(desc)}", flush=True)

    f_precos.close()
    f_anom.close()
    f_rem.close()
    bytes_gz += len(gz.flush())

    with open(SAIDA / "produtos.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["id", "codigo", "nome", "unidade", "nome_anp"])
        for nome_anp, (pid, cod, nome, un, *_r) in sorted(PRODUTOS.items(), key=lambda kv: kv[1][0]):
            w.writerow([pid, cod, nome, un, nome_anp])

    campos = ["razao_social", "bandeira", "logradouro", "numero", "complemento", "bairro",
              "municipio", "uf", "cep", "primeira_coleta", "ultima_coleta"]
    with open(SAIDA / "postos.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["id", "cnpj"] + campos)
        for cnpj, i in sorted(posto_id.items(), key=lambda kv: kv[1]):
            p = postos[cnpj]
            w.writerow([i, cnpj] + [p[c].isoformat() if isinstance(p[c], date) else p[c] for c in campos])

    rel["removidos"] = dict(rel.pop("descartes"))
    rel["anomalias_por_motivo"] = dict(anom_por_motivo)
    rel["totais"] = {
        "linhas_lidas": sum(s["linhas_lidas"] for s in rel["por_semestre"].values()),
        "precos_mantidos": total_saida,
        "precos_anomalos": sum(s["precos_anomalos"] for s in rel["por_semestre"].values()),
        "postos_unicos": len(posto_id),
        "precos_csv_bytes": bytes_csv,
        "precos_csv_gzip_bytes": bytes_gz,
        "bandeiras": Counter(p["bandeira"] for p in postos.values()).most_common(),
        "postos_por_uf": dict(sorted(Counter(p["uf"] for p in postos.values()).items())),
        "postos_com_coleta_desde_2025_07": sum(1 for p in postos.values() if p["ultima_coleta"] >= date(2025, 7, 1)),
    }
    (SAIDA / "relatorio.json").write_text(json.dumps(rel, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in rel["totais"].items() if k not in ("bandeiras", "postos_por_uf")}, indent=2))
    print("removidos:", rel["removidos"])
    print("anomalias:", rel["anomalias_por_motivo"])


if __name__ == "__main__":
    main()
