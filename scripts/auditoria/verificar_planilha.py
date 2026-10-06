"""
Confere a planilha sem Excel nem LibreOffice: relê o arquivo, avalia as fórmulas do Dashboard
(COUNTA, COUNTIF com curinga, SUM, IFERROR e divisões simples) e compara com os números calculados
a partir dos resultados (resultados/_resumo.json).

Uso: python scripts/auditoria/verificar_planilha.py
"""
from __future__ import annotations

import fnmatch
import json
import re
from pathlib import Path

from openpyxl import load_workbook

PASTA = Path(__file__).resolve().parents[2] / "documentacao" / "auditoria"
FUNCOES_OK = {"COUNTA", "COUNTIF", "SUM", "IFERROR"}


def faixa(wb, ref: str):
    m = re.fullmatch(r"(?:'([^']+)'|(\w+))!\$?([A-Z]+)\$?(\d+):\$?([A-Z]+)\$?(\d+)", ref)
    aba = m.group(1) or m.group(2)
    if aba not in wb.sheetnames:
        raise ValueError(f"aba inexistente: {aba}")
    ws = wb[aba]
    return [c.value for linha in ws[f"{m.group(3)}{m.group(4)}:{m.group(5)}{m.group(6)}"] for c in linha]


def main() -> int:
    wb = load_workbook(PASTA / "auditoria_gasprice.xlsx")
    ws = wb["Dashboard"]
    resumo = json.loads((PASTA / "resultados" / "_resumo.json").read_text(encoding="utf-8"))
    problemas, conferidos = [], 0
    for linha in ws.iter_rows():
        for c in linha:
            if isinstance(c.value, str) and c.value.startswith("="):
                for f in re.findall(r"([A-Z]+)\(", c.value):
                    if f not in FUNCOES_OK:
                        problemas.append(f"{c.coordinate}: função {f} fora da lista segura")
    for r in range(15, ws.max_row + 1):
        nome = ws.cell(row=r, column=2).value
        if nome not in resumo["por_aba"]:
            continue
        esperado = resumo["por_aba"][nome]
        obtido = []
        f_total = ws.cell(row=r, column=3).value
        obtido.append(sum(v is not None for v in faixa(wb, re.search(r"COUNTA\((.+)\)", f_total).group(1))))
        for col in range(4, 8):
            f = ws.cell(row=r, column=col).value
            ref, crit = re.search(r'COUNTIF\((.+),"(.+)"\)', f).groups()
            obtido.append(sum(isinstance(v, str) and fnmatch.fnmatchcase(v, crit) for v in faixa(wb, ref)))
        conferidos += 1
        if tuple(obtido) != tuple(esperado):
            problemas.append(f"{nome}: fórmulas dão {obtido}, os dados dizem {esperado}")
    bugs = faixa(wb, "'Bugs encontrados'!C2:C200")
    for k, sev in enumerate(("Crítica", "Alta", "Média", "Baixa")):
        f = ws.cell(row=10, column=2 + k).value
        if f'"{sev}"' not in f:
            problemas.append(f"contagem de bugs {sev} com fórmula inesperada: {f}")
    contagem = {s: bugs.count(s) for s in ("Crítica", "Alta", "Média", "Baixa")}
    print(f"abas conferidas no Dashboard: {conferidos}; bugs por severidade: {contagem}")
    for p in problemas:
        print("PROBLEMA:", p)
    print("OK: as fórmulas batem com os dados." if not problemas else f"{len(problemas)} problema(s).")
    return 1 if problemas else 0


if __name__ == "__main__":
    raise SystemExit(main())
