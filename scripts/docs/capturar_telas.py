"""
Captura as telas do app (build web no modo demonstração) para documentacao/telas, no tema claro e no escuro.

Usa duas builds: visitante (app/build/web_visitante) e logado (app/build/web_logado). Com --build, compila as duas
antes. Serve cada uma num servidor local, abre no Edge pelo Playwright e grava WebP em documentacao/telas (claro)
e documentacao/telas/escuro. Depois rode scripts/docs/gerar_telas.py para montar a página.

Requer: Flutter, Python com playwright e pillow, e o Microsoft Edge instalado.

Uso:
  python scripts/docs/capturar_telas.py --build
  python scripts/docs/capturar_telas.py claro --so=04-mapa,04c-mapa-diesel
"""
from __future__ import annotations

import functools
import subprocess
import sys
import tempfile
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

RAIZ = Path(__file__).resolve().parents[2]
APP = RAIZ / "app"
DESTINO = RAIZ / "documentacao" / "telas"
BUILDS = {"visitante": ("web_visitante", []), "logado": ("web_logado", ["--dart-define=DEMO_LOGADO=true"])}
# O MapLibre precisa de WebGL: no Edge sem janela, pelo SwiftShader
ARGS = ["--enable-unsafe-swiftshader", "--use-angle=swiftshader", "--ignore-gpu-blocklist"]
CEL = (390, 844, 2)
TAB = (1194, 834, 1.5)
# Só estas entram no conjunto escuro
ESCURO = {"02-busca", "04-mapa", "04b-mapa-posto", "04c-mapa-diesel", "05-posto", "06-contribuicoes", "08-historico",
          "23-perfil", "33-tablet-mapa"}

SIMPLES = [
    ("01-boas-vindas", "/boas-vindas"), ("02-busca", "/buscar"), ("05-posto", "/posto/1"),
    ("07-posto-estimativa", "/posto/6"), ("08-historico", "/posto/1/historico?produto=1"),
    ("09-avaliacoes", "/posto/1/avaliacoes"), ("10-avaliar", "/posto/1/avaliar"), ("14-entrar", "/entrar"),
    ("15-cadastro", "/cadastro"), ("16-recuperar-senha", "/recuperar-senha"), ("17-perfil-visitante", "/perfil"),
    ("18-ranking", "/ranking"), ("19-favoritos", "/favoritos"), ("20-sobre", "/sobre"),
    ("21-posto-aproximado", "/posto/4"), ("22-posicao-posto", "/posto/4/posicao"),
]
TABLET = [("30-tablet-posto", "/posto/1"), ("31-tablet-busca", "/buscar"), ("32-tablet-cadastro", "/cadastro")]
LOGADO = [
    ("23-perfil", "/perfil"), ("24-editar-perfil", "/perfil/editar"), ("25-alterar-senha", "/perfil/senha"),
    ("26-pontos", "/pontos"), ("27-avisos", "/notificacoes"), ("19b-favoritos-lista", "/favoritos"),
    ("28-nova-senha", "/nova-senha"), ("29-verificar-email", "/verificar-email?email=carla.m%40exemplo.com"),
]


def compilar() -> None:
    for pasta, extras in BUILDS.values():
        cmd = ["flutter", "build", "web", "--release", "--no-wasm-dry-run", "--dart-define=DEMO=true", *extras,
               "--output", f"build/{pasta}"]
        print(" ".join(cmd), flush=True)
        subprocess.run(cmd, cwd=APP, check=True, shell=sys.platform == "win32")


def servir(pasta: Path) -> tuple[ThreadingHTTPServer, str]:
    class Silencioso(SimpleHTTPRequestHandler):
        def log_message(self, *_):  # noqa: D102
            pass

    servidor = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Silencioso, directory=str(pasta)))
    threading.Thread(target=servidor.serve_forever, daemon=True).start()
    return servidor, f"http://127.0.0.1:{servidor.server_address[1]}/#"


def para_webp(png: Path, destino: Path) -> None:
    im = Image.open(png).convert("RGB")
    tamanho = (1200, 838) if png.name.startswith("3") else (520, 1125)
    im.resize(tamanho, Image.LANCZOS).save(destino / f"{png.stem}.webp", "WEBP", quality=82, method=6)


def capturar(tema: str, base: dict[str, str], pngs: Path, so: set[str] | None) -> None:
    esquema = "dark" if tema == "escuro" else "light"

    def quer(nome: str) -> bool:
        return (tema != "escuro" or nome in ESCURO) and (not so or nome in so)

    with sync_playwright() as p:
        nav = p.chromium.launch(channel="msedge", headless=True, args=ARGS)

        def abrir(build, rota, tela, espera=4500, produto=None):
            w, h, escala = tela
            ctx = nav.new_context(viewport={"width": w, "height": h}, device_scale_factor=escala, locale="pt-BR",
                                  color_scheme=esquema)
            ctx.add_init_script("localStorage.setItem('flutter.viu_boas_vindas', 'true')")
            if produto:
                ctx.add_init_script(f"localStorage.setItem('flutter.produto', '{produto}')")
            pg = ctx.new_page()
            pg.goto(base[build] + rota)
            pg.wait_for_selector("flutter-view", timeout=60000)
            pg.wait_for_timeout(espera)
            return ctx, pg

        def foto(pg, nome):
            pg.screenshot(path=str(pngs / f"{nome}.png"))
            print("ok", tema, nome, flush=True)

        def semantica(pg):
            """Liga a árvore de acessibilidade do Flutter web para clicar pelos rótulos."""
            pg.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
            pg.wait_for_timeout(1500)

        def afastar(pg):
            """Zoom de 12 para ~11, para caberem os cinco postos de Fortaleza da demonstração."""
            pg.mouse.move(195, 470)
            for _ in range(3):
                pg.mouse.wheel(0, 450)
                pg.wait_for_timeout(700)
            pg.wait_for_timeout(8000)

        def tentar(nome, passos):
            try:
                passos()
            except Exception as erro:  # noqa: BLE001
                print("falhou", tema, nome, erro, flush=True)

        for nome, rota in SIMPLES:
            if quer(nome):
                ctx, pg = abrir("visitante", rota, CEL)
                foto(pg, nome)
                ctx.close()

        # Mapa: espera os blocos vetoriais do OpenFreeMap carregarem
        if quer("04-mapa"):
            ctx, pg = abrir("visitante", "/", CEL, 9000)
            afastar(pg)
            foto(pg, "04-mapa")

            def selecionar():
                semantica(pg)
                # Pino no alto da tela, para o anel de seleção não ficar sob o cartão
                pg.get_by_role("button", name="Posto Beira Mar").first.click()
                pg.wait_for_timeout(2500)
                foto(pg, "04b-mapa-posto")

            tentar("04b-mapa-posto", selecionar)
            ctx.close()

        # Diesel S10 na demonstração: um preço de 9 dias (contorno vermelho) e postos sem preço (contorno cinza)
        if quer("04c-mapa-diesel"):
            ctx, pg = abrir("visitante", "/", CEL, 9000, produto=5)
            afastar(pg)
            foto(pg, "04c-mapa-diesel")
            ctx.close()

        if quer("33-tablet-mapa"):
            ctx, pg = abrir("visitante", "/", TAB, 12000)
            foto(pg, "33-tablet-mapa")
            ctx.close()

        if quer("03-filtros"):
            def filtros():
                ctx, pg = abrir("visitante", "/buscar", CEL)
                semantica(pg)
                pg.get_by_role("button", name="Filtros").click()
                pg.wait_for_timeout(1500)
                foto(pg, "03-filtros")
                ctx.close()

            tentar("03-filtros", filtros)

        if quer("06-contribuicoes"):
            def contribuicoes():
                ctx, pg = abrir("visitante", "/posto/1", CEL)
                semantica(pg)
                pg.get_by_text("Gasolina comum").first.click()
                pg.wait_for_timeout(1800)
                foto(pg, "06-contribuicoes")
                ctx.close()

            tentar("06-contribuicoes", contribuicoes)

        if quer("11-enviar-instrucoes"):
            def envio():
                ctx, pg = abrir("visitante", "/posto/1/enviar", CEL)
                foto(pg, "11-enviar-instrucoes")
                semantica(pg)
                pg.get_by_role("button", name="Abrir câmera").click()
                pg.wait_for_timeout(2000)
                foto(pg, "12-enviar-revisao")
                pg.get_by_role("button", name="Enviar preços").click()
                pg.wait_for_timeout(2000)
                foto(pg, "13-enviar-concluido")
                ctx.close()

            tentar("fluxo de envio", envio)

        for nome, rota in TABLET:
            if quer(nome):
                ctx, pg = abrir("visitante", rota, TAB)
                foto(pg, nome)
                ctx.close()

        for nome, rota in LOGADO:
            if quer(nome):
                ctx, pg = abrir("logado", rota, CEL)
                foto(pg, nome)
                ctx.close()
        nav.close()


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:]
    so = next((set(a.split("=", 1)[1].split(",")) for a in args if a.startswith("--so=")), None)
    temas = [a for a in args if not a.startswith("--")] or ["claro", "escuro"]
    if "--build" in args:
        compilar()
    base = {}
    for nome, (pasta, _) in BUILDS.items():
        if not (APP / "build" / pasta / "index.html").exists():
            print(f"Falta a build {pasta}: rode com --build")
            return 1
        base[nome] = servir(APP / "build" / pasta)[1]
    with tempfile.TemporaryDirectory() as tmp:
        for tema in temas:
            pngs = Path(tmp) / tema
            pngs.mkdir()
            capturar(tema, base, pngs, so)
            destino = DESTINO / "escuro" if tema == "escuro" else DESTINO
            destino.mkdir(parents=True, exist_ok=True)
            for png in sorted(pngs.glob("*.png")):
                para_webp(png, destino)
            print(f"{tema}: {len(list(pngs.glob('*.png')))} imagens em {destino}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
