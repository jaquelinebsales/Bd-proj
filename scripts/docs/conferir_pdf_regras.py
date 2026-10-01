"""
Confere se o PDF das regras contém tudo o que a página HTML tem: cada regra, valor, parâmetro,
entidade e campo do diagrama, e cada trecho de texto da página.

Uso: python scripts/docs/conferir_pdf_regras.py      (depois de gerar_regras.py e gerar_pdf_regras.py)
Sai com código 1 se algo estiver faltando.
"""
from __future__ import annotations

import html
import re
import sys
from pathlib import Path

import pymupdf

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
import gerar_regras as g  # noqa: E402


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip().lower()


def main() -> int:
    pdf = pymupdf.open(RAIZ / "documentacao" / "regras_de_negocio.pdf")
    bruto = " ".join(p.get_text() for p in pdf)
    T = norm(bruto)
    T_sem_espacos = T.replace(" ", "")
    faltam: list[str] = []

    n = 0
    for grupo, lista in g.REGRAS:
        if norm(grupo) not in T:
            faltam.append("grupo: " + grupo)
        for texto, _onde, valor in lista:
            n += 1
            if norm(texto) not in T:
                faltam.append(f"RN-{n:02d}: {texto[:60]}")
            if valor and norm(valor) not in T:
                faltam.append(f"valor de RN-{n:02d}: {valor}")
    ids = {m for m in re.findall(r"RN-(\d\d)", bruto)}
    print(f"regras no catálogo: {n}; ids RN no PDF: {len(ids)}")

    sql = (RAIZ / "supabase" / "migrations" / "20260929000003_regras.sql").read_text(encoding="utf-8")
    trecho = sql[sql.index("insert into public.parametros"):]
    params = re.findall(r"\('(\w+)',\s*([-\d.]+),\s*'([^']*)'\)", trecho)
    for k, _v, d in params:
        if norm(k) not in T:
            faltam.append("parâmetro: " + k)
        if norm(d) not in T:
            faltam.append("descrição do parâmetro: " + k)
    print(f"parâmetros: {len(params)}")

    for nome, (_col, _y, campos, _dest, etiqueta) in g.ENTIDADES.items():
        if norm(nome) not in T:
            faltam.append("entidade: " + nome)
        for campo, _chave in campos:
            if norm(campo) not in T:
                faltam.append(f"campo {nome}.{campo}")
        if etiqueta and norm(etiqueta) not in T:
            faltam.append("etiqueta: " + etiqueta)
    print(f"entidades no diagrama: {len(g.ENTIDADES)}")

    pagina = (RAIZ / "documentacao" / "regras_de_negocio.html").read_text(encoding="utf-8")
    pagina = re.sub(r"<script.*?</script>|<style.*?</style>|<svg.*?</svg>", " ", pagina, flags=re.S)
    blocos = re.findall(r"<(h1|h2|h3|p|li|figcaption|td|th)\b[^>]*>(.*?)</\1>", pagina, flags=re.S)
    conferidos = 0
    for _tag, corpo in blocos:
        limpo = norm(html.unescape(re.sub(r"<[^>]+>", " ", corpo)))
        if len(limpo) < 4:
            continue
        conferidos += 1
        if limpo in T or limpo.replace(" ", "") in T_sem_espacos:
            continue   # cabeçalhos com espaçamento entre letras saem com espaços extras na extração
        palavras = limpo.split()
        if not all(" ".join(palavras[i:i + 4]) in T for i in range(0, max(len(palavras) - 3, 1), 4)):
            faltam.append("texto da página: " + limpo[:80])
    print(f"blocos de texto da página conferidos: {conferidos}; páginas do PDF: {pdf.page_count}")

    print()
    if faltam:
        print(f"FALTAM {len(faltam)} itens:")
        for f in faltam[:40]:
            print(" -", f)
        return 1
    print("Nada falta: tudo o que está na página está no PDF.")
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
