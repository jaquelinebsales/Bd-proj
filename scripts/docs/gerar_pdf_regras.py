"""
Gera documentacao/regras_de_negocio.pdf a partir da página documentacao/regras_de_negocio.html.

O PDF traz tudo o que a página tem: diagramas, catálogo completo de regras, tabelas e parâmetros.
Usa o navegador Edge/Chrome pelo Playwright, com os estilos de impressão da própria página (A4 em paisagem).

Uso: python scripts/docs/gerar_pdf_regras.py     (rode antes: python scripts/docs/gerar_regras.py)
Requer: pip install playwright   e o Microsoft Edge ou Google Chrome instalado.
"""
from __future__ import annotations

import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

RAIZ = Path(__file__).resolve().parents[2]
ORIGEM = RAIZ / "documentacao" / "regras_de_negocio.html"
DESTINO = RAIZ / "documentacao" / "regras_de_negocio.pdf"

ESQUELETO = ('<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">'
             '<meta name="viewport" content="width=device-width, initial-scale=1">'
             '<style>:root{color-scheme:light}body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style>'
             '</head><body>')

RODAPE = ('<div style="width:100%;font-size:8px;color:#6b7a73;padding:0 11mm;display:flex;justify-content:space-between;'
          'font-family:Arial,sans-serif"><span>gasprice · Regras de negócio</span>'
          '<span>página <span class="pageNumber"></span> de <span class="totalPages"></span></span></div>')


def main() -> int:
    if not ORIGEM.exists():
        print("Gere a página antes: python scripts/docs/gerar_regras.py")
        return 1
    html = ESQUELETO + ORIGEM.read_text(encoding="utf-8") + "</body></html>"
    temporario = ORIGEM.with_name("_regras_para_pdf.html")
    temporario.write_text(html, encoding="utf-8")
    try:
        with sync_playwright() as p:
            navegador = None
            for canal in ("msedge", "chrome"):
                try:
                    navegador = p.chromium.launch(channel=canal, headless=True)
                    break
                except Exception:  # noqa: BLE001
                    continue
            if navegador is None:
                print("Não encontrei o Edge nem o Chrome instalados.")
                return 1
            ctx = navegador.new_context(color_scheme="light", viewport={"width": 1123, "height": 794})
            pg = ctx.new_page()
            pg.goto(temporario.as_uri())
            pg.wait_for_load_state("networkidle")
            pg.evaluate("document.fonts.ready")
            pg.emulate_media(media="print")
            pg.pdf(path=str(DESTINO), format="A4", landscape=True, print_background=True,
                   margin={"top": "12mm", "bottom": "14mm", "left": "11mm", "right": "11mm"},
                   display_header_footer=True, header_template="<span></span>", footer_template=RODAPE)
            navegador.close()
    finally:
        temporario.unlink(missing_ok=True)
    print(f"{DESTINO} ({DESTINO.stat().st_size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
