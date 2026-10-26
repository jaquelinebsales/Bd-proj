"""
Gera as imagens do portfólio em portfolio/ (PNG em 2x): telas do app no modo demonstração e o diagrama de arquitetura.

Usa as builds web de capturar_telas.py (app/build/web_visitante e web_logado). Com --build, compila antes.
O mapa abre a folha de um posto tocando nos pinos e a expande com um arrasto de toque.

Uso:
  py -3.12 scripts/docs/capturar_portfolio.py [--build] [--so=01-mapa,12-arquitetura]
"""
from __future__ import annotations

import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capturar_telas as ct  # noqa: E402

RAIZ = ct.RAIZ
DESTINO = RAIZ / "portfolio"
DIAGRAMA = Path(__file__).resolve().parent / "portfolio_arquitetura.html"
POSTO_FOLHA = "Posto Vale Verde"
# Builds próprias: modo demonstração sem a faixa "DEMO" no canto
BUILDS = {"visitante": ("web_portfolio_visitante", []),
          "logado": ("web_portfolio_logado", ["--dart-define=DEMO_LOGADO=true"])}


def compilar() -> None:
    import subprocess
    for pasta, extras in BUILDS.values():
        cmd = ["flutter", "build", "web", "--release", "--no-wasm-dry-run", "--dart-define=DEMO=true",
               "--dart-define=SEM_FAIXA_DEMO=true", *extras, "--output", f"build/{pasta}"]
        print(" ".join(cmd), flush=True)
        subprocess.run(cmd, cwd=ct.APP, check=True, shell=sys.platform == "win32")


def como_print(caminho: Path, escala: float) -> None:
    """Acrescenta a barra de status do Android (hora, sinal, Wi-Fi e bateria) no topo, na cor do topo da tela."""
    from PIL import Image, ImageDraw, ImageFont

    tela = Image.open(caminho).convert("RGB")
    a = round(24 * escala)
    fundo = tela.getpixel((4, 4))
    claro = sum(fundo) / 3 > 140
    tinta = (32, 33, 36) if claro else (232, 234, 237)
    nova = Image.new("RGB", (tela.width, tela.height + a), fundo)
    nova.paste(tela, (0, a))
    d = ImageDraw.Draw(nova)
    fonte = ImageFont.truetype(r"C:\Windows\Fonts\seguisb.ttf", round(13 * escala))
    m = round(16 * escala)
    d.text((m, a / 2), "9:41", font=fonte, fill=tinta, anchor="lm")
    u = escala
    # Bateria
    xb, yb, wb, hb = tela.width - m - 22 * u, a / 2 - 5.5 * u, 20 * u, 11 * u
    d.rounded_rectangle([xb, yb, xb + wb, yb + hb], radius=2.5 * u, outline=tinta, width=max(1, round(1.2 * u)))
    d.rounded_rectangle([xb + 2 * u, yb + 2 * u, xb + wb * 0.78, yb + hb - 2 * u], radius=1.2 * u, fill=tinta)
    d.rectangle([xb + wb + 0.6 * u, yb + 3.5 * u, xb + wb + 2.2 * u, yb + hb - 3.5 * u], fill=tinta)
    # Sinal
    xs = xb - 26 * u
    for i in range(4):
        h = (3 + i * 2.6) * u
        d.rectangle([xs + i * 4 * u, a / 2 + 5.5 * u - h, xs + i * 4 * u + 2.6 * u, a / 2 + 5.5 * u], fill=tinta)
    # Wi-Fi
    cx, cy = xs - 14 * u, a / 2 + 5 * u
    d.pieslice([cx - 9 * u, cy - 9 * u, cx + 9 * u, cy + 9 * u], 225, 315, fill=tinta)
    nova.save(caminho)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:]
    so = next((set(a.split("=", 1)[1].split(",")) for a in args if a.startswith("--so=")), None)
    if "--build" in args:
        compilar()
    base = {nome: ct.servir(ct.APP / "build" / pasta)[1] for nome, (pasta, _) in BUILDS.items()}
    DESTINO.mkdir(exist_ok=True)

    def quer(nome: str) -> bool:
        return not so or nome in so

    with sync_playwright() as p:
        nav = p.chromium.launch(channel="msedge", headless=True, args=ct.ARGS)

        def abrir(build, rota, tela=ct.CEL, tema="light", espera=4500, toque=False):
            w, h, escala = tela
            ctx = nav.new_context(viewport={"width": w, "height": h}, device_scale_factor=escala, locale="pt-BR",
                                  color_scheme=tema, has_touch=toque)
            ctx.add_init_script("localStorage.setItem('flutter.viu_boas_vindas', 'true')")
            pg = ctx.new_page()
            pg.goto(base[build] + rota)
            pg.wait_for_selector("flutter-view", timeout=60000)
            pg.wait_for_timeout(espera)
            return ctx, pg

        def foto(pg, nome):
            arq = DESTINO / f"{nome}.png"
            pg.screenshot(path=str(arq))
            como_print(arq, pg.evaluate("window.devicePixelRatio"))
            print("ok", nome, flush=True)

        def semantica(pg):
            pg.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
            pg.wait_for_timeout(1500)

        def folha_aberta(pg) -> bool:
            return pg.get_by_role("button", name="Ver detalhes").count() > 0 and pg.get_by_text(POSTO_FOLHA).count() > 0

        def arrastar(pg, x, y0, y1):
            cdp = pg.context.new_cdp_session(pg)
            passos = 14
            cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x, "y": y0}]})
            for i in range(1, passos + 1):
                y = y0 + (y1 - y0) * i / passos
                cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": x, "y": y}]})
                pg.wait_for_timeout(25)
            cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            pg.wait_for_timeout(1500)

        def mapa(tema, sufixo):
            ctx, pg = abrir("visitante", "/", tema=tema, espera=9000, toque=True)
            # Na demonstração o mapa já abre enquadrado ao sul do centro de Fortaleza, com todos os postos
            pg.wait_for_timeout(4000)
            semantica(pg)
            # Procura o pino do posto em espiral a partir de onde o centro deve ter ido parar
            achou = False
            for r in range(0, 220, 12):
                pontos = [(195, 290)] if r == 0 else [(195 + dx, 290 + dy) for dx, dy in
                                                     ((r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, -r), (r, -r), (-r, r))]
                for x, y in pontos:
                    pg.mouse.click(x, y)
                    pg.wait_for_timeout(500)
                    if folha_aberta(pg):
                        achou = True
                        break
                if achou:
                    break
            if not achou:
                pg.screenshot(path=str(ct.RAIZ / "app" / "build" / f"portfolio_mapa_falhou_{sufixo}.png"))
                print("falhou: pino do", POSTO_FOLHA, "não encontrado (tela em app/build)", flush=True)
                ctx.close()
                return
            pg.wait_for_timeout(1500)
            foto(pg, f"01-mapa-{sufixo}")
            caixa = pg.get_by_text(POSTO_FOLHA).last.bounding_box()
            arrastar(pg, caixa["x"] + 20, caixa["y"] + 8, 90)
            foto(pg, f"02-mapa-folha-expandida-{sufixo}")
            ctx.close()

        for tema, sufixo in (("light", "claro"), ("dark", "escuro")):
            if quer("01-mapa") or quer(f"01-mapa-{sufixo}"):
                mapa(tema, sufixo)

        if quer("03-contribuicoes"):
            ctx, pg = abrir("visitante", "/posto/1")
            semantica(pg)
            pg.get_by_text("Gasolina comum").first.click()
            pg.wait_for_timeout(1800)
            foto(pg, "03-contribuicoes")
            ctx.close()

        if quer("04-posto-estimativa"):
            ctx, pg = abrir("visitante", "/posto/7")
            foto(pg, "04-posto-estimativa")
            ctx.close()

        if quer("05-envio-revisao"):
            ctx, pg = abrir("visitante", "/posto/1/enviar")
            semantica(pg)
            pg.get_by_role("button", name="Abrir câmera").click()
            pg.wait_for_timeout(2000)
            foto(pg, "05-envio-revisao")
            ctx.close()

        if quer("06-historico"):
            ctx, pg = abrir("visitante", "/posto/1/historico?produto=1")
            foto(pg, "06-historico")
            ctx.close()

        if quer("07-busca"):
            ctx, pg = abrir("visitante", "/buscar")
            foto(pg, "07-busca")
            ctx.close()

        if quer("08-busca-filtros"):
            ctx, pg = abrir("visitante", "/buscar")
            semantica(pg)
            pg.get_by_role("button", name="Filtros").click()
            pg.wait_for_timeout(1500)
            foto(pg, "08-busca-filtros")
            ctx.close()

        if quer("09-tablet-mapa"):
            ctx, pg = abrir("visitante", "/", tela=ct.TAB, espera=14000)
            foto(pg, "09-tablet-mapa")
            ctx.close()

        if quer("10-perfil"):
            ctx, pg = abrir("logado", "/perfil")
            foto(pg, "10-perfil")
            ctx.close()

        if quer("11-pontos"):
            ctx, pg = abrir("logado", "/pontos")
            foto(pg, "11-pontos")
            ctx.close()

        if quer("12-arquitetura"):
            for tema, sufixo in (("light", "claro"), ("dark", "escuro")):
                ctx = nav.new_context(viewport={"width": 1600, "height": 960}, device_scale_factor=2, color_scheme=tema)
                pg = ctx.new_page()
                pg.goto(DIAGRAMA.as_uri())
                pg.wait_for_timeout(800)
                pg.locator("#diagrama").screenshot(path=str(DESTINO / f"12-arquitetura-{sufixo}.png"))
                print("ok", f"12-arquitetura-{sufixo}", flush=True)
                ctx.close()
        nav.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
