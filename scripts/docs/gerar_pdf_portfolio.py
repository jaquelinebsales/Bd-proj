"""
Gera portfolio/gasprice_portfolio.pdf a partir de scripts/docs/portfolio_template.html e das imagens de portfolio/.

Rode antes: py -3.12 scripts/docs/capturar_portfolio.py
Uso: py -3.12 scripts/docs/gerar_pdf_portfolio.py
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from playwright.sync_api import sync_playwright

RAIZ = Path(__file__).resolve().parents[2]
PASTA = RAIZ / "portfolio"
MODELO = Path(__file__).resolve().parent / "portfolio_template.html"
DESTINO = PASTA / "gasprice_portfolio.pdf"


def main() -> int:
    html = MODELO.read_text(encoding="utf-8").replace("{{P}}", PASTA.as_uri())
    with tempfile.TemporaryDirectory() as tmp:
        pagina = Path(tmp) / "portfolio.html"
        pagina.write_text(html, encoding="utf-8")
        with sync_playwright() as p:
            nav = p.chromium.launch(channel="msedge", headless=True)
            pg = nav.new_page()
            pg.goto(pagina.as_uri())
            pg.wait_for_load_state("networkidle")
            pg.pdf(path=str(DESTINO), format="A4", print_background=True, prefer_css_page_size=True,
                   display_header_footer=True, header_template="<span></span>",
                   footer_template='<div style="width:100%;font-size:7.5pt;color:#7A8594;padding:0 16mm;'
                                   'font-family:Segoe UI,Arial;display:flex;justify-content:space-between">'
                                   '<span>GasPrice · portfólio</span>'
                                   '<span><span class="pageNumber"></span> de <span class="totalPages"></span></span></div>')
            nav.close()
    print(f"{DESTINO} ({DESTINO.stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
