"""
Gera a pasta demonstracao/ (fora do Git): a demonstração web do app para o portfólio.

- demonstracao/app/: build web do modo demonstração, já logada como a usuária fictícia, sem servidor.
- demonstracao/index.html e assets/: a página (React, Tailwind e three.js, em scripts/docs/demonstracao_web), com o
  aparelho em 3D que se abre de celular em tablet e o painel que acompanha a arquitetura ao vivo.

O endereço base é relativo ("./"), então a pasta funciona em qualquer caminho do site.
A página é compilada com o Deno (dev-tools/deno), que roda o Vite sem precisar do Node.

Uso: py -3.12 scripts/docs/gerar_demonstracao.py [--sem-build] [--sem-previas]
  --sem-build: não recompila o Flutter; --sem-previas: mantém as imagens de prévia que já existem em previa/
"""
from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
APP = RAIZ / "app"
DESTINO = RAIZ / "demonstracao"
BUILD = APP / "build" / "web_demonstracao"
PAGINA = Path(__file__).resolve().parent / "demonstracao_web"
FLUTTER = Path(os.environ.get("FLUTTER", Path.home() / "dev-tools" / "flutter" / "bin" / "flutter.bat"))
DENO = Path(os.environ.get("DENO", Path.home() / "dev-tools" / "deno" / "deno.exe"))

DENSIDADE = """
  <script>
    // Na moldura da demonstração: desenha na densidade em que o app aparece (escala × DPR, recebida da página
    // por mensagem, que funciona também com a página em outro site) e abre direto no mapa
    (function () {
      if (window.parent === window) return;
      // Contextos WebGL de teste: o carregador e o motor do Flutter só perguntam se há WebGL numa tela 1×1 solta e a
      // abandonam. Abandonados, contam no limite de contextos ativos do navegador até o coletor de lixo passar, e
      // passando do limite (baixo em tablets) o navegador apaga o mais antigo: a cena 3D da página, o corpo dos
      // aparelhos. Soltos aqui logo depois da pergunta, os dois apps ficam com só os contextos que usam.
      var obterContexto = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (tipo) {
        var gl = obterContexto.apply(this, arguments), tela = this;
        if (gl && /webgl/.test(tipo) && !tela.isConnected && tela.width <= 1 && tela.height <= 1) {
          setTimeout(function () {
            if (tela.isConnected || tela.width > 1 || tela.height > 1 || gl.isContextLost()) return;
            var soltar = gl.getExtension('WEBGL_lose_context');
            if (soltar) soltar.loseContext();
          }, 0);
        }
        return gl;
      };
      var busca = new URLSearchParams(location.search);
      var inicial = Number(busca.get('dpr'));
      var atual = inicial > 0 ? inicial : (window.devicePixelRatio || 1);
      Object.defineProperty(window, 'devicePixelRatio', { configurable: true, get: function () { return atual; } });
      // Escala em que o aparelho aparece na página: o app desenha já nesse tamanho (pixel a pixel, sem a página
      // reduzir a imagem dele), lendo window.__escalaApp (app/lib/servicos/monitor_demo_saida_web.dart)
      var escala = Number(busca.get('escala'));
      window.__escalaApp = escala > 0 ? escala : 1;
      try { localStorage.setItem('flutter.viu_boas_vindas', 'true'); } catch (e) {}
      function mapasVivos() {
        return (window.__mapasDemo || []).filter(function (m) { try { return m.getContainer().isConnected; } catch (e) { return false; } });
      }
      function redimensionar() {
        window.dispatchEvent(new Event('resize'));
        if (window.visualViewport) window.visualViewport.dispatchEvent(new Event('resize'));
        // o mapa não muda de tamanho em dp quando só a escala muda: redesenha na nova densidade
        (window.__mapasDemo || []).forEach(function (m) { try { m.resize(); } catch (e) {} });
      }
      // Página travada no aparelho (App.jsx): a roda sempre fica no app, mesmo sem clique nele
      var travado = false;
      window.addEventListener('message', function (ev) {
        var d = ev.data;
        if (ev.source !== window.parent || !d || d.fonte !== 'gasprice-moldura') return;
        if (d.tipo === 'travar') { travado = !!d.valor; return; }
        // Tela cheia por cima: guarda onde o mapa está e, na volta, põe ele de novo ali (escondido, o navegador
        // do celular pode ter descartado o desenho dele, e o mapa refeito abriria fora dos postos)
        if (d.tipo === 'guardar') {
          var m0 = mapasVivos()[0];
          if (m0) window.__cameraDemo = { center: m0.getCenter(), zoom: m0.getZoom() };
          return;
        }
        if (d.tipo === 'reavivar') {
          redimensionar();
          var repor = function () {
            mapasVivos().forEach(function (m) {
              try { if (window.__cameraDemo) m.jumpTo(window.__cameraDemo); m.triggerRepaint(); } catch (e) {}
            });
          };
          repor();
          setTimeout(repor, 700);
          setTimeout(repor, 1800);
          return;
        }
        if (!(d.valor > 0)) return;
        if (d.tipo === 'densidade' && d.valor !== atual) { atual = d.valor; redimensionar(); }
        if (d.tipo === 'escala' && d.valor !== window.__escalaApp) {
          window.__escalaApp = d.valor;
          if (window.__aoMudarEscala) window.__aoMudarEscala();
          redimensionar();
        }
      });
      // A roda do mouse sobre o aparelho rola a página (como num vídeo embutido). Depois de um clique no app, ela
      // move o mapa e as listas até o cursor sair do aparelho; Ctrl + roda sempre dá zoom no mapa.
      var focado = false;
      window.addEventListener('pointerdown', function () { focado = true; }, true);
      document.addEventListener('mouseleave', function () { focado = false; });
      window.addEventListener('blur', function () { focado = false; });
      window.addEventListener('wheel', function (ev) {
        if (focado || travado || ev.ctrlKey) return;
        ev.preventDefault();
        ev.stopImmediatePropagation();
        var f = ev.deltaMode === 1 ? 40 : ev.deltaMode === 2 ? window.innerHeight : 1;
        window.parent.postMessage({ fonte: 'gasprice-app', tipo: 'rolar', dy: ev.deltaY * f }, '*');
      }, { capture: true, passive: false });
      // Duplo toque (dedo, dois toques curtos e parados no mesmo lugar): a página abre o app em tela cheia.
      // Tempo do próprio toque (timeStamp), não o de quando o evento é tratado: num celular mais lento o app ocupa a
      // página por ~300 ms depois do primeiro toque, e o segundo chegava "atrasado" e não contava
      var inicio = null, ultimo = null;
      window.addEventListener('pointerdown', function (ev) {
        inicio = ev.pointerType === 'touch' ? { t: ev.timeStamp, x: ev.clientX, y: ev.clientY } : null;
      }, true);
      window.addEventListener('pointerup', function (ev) {
        var agora = ev.timeStamp;
        if (!inicio || agora - inicio.t > 300 || Math.abs(ev.clientX - inicio.x) > 12 || Math.abs(ev.clientY - inicio.y) > 12) {
          ultimo = null;
          return;
        }
        if (ultimo && agora - ultimo.t < 350 && Math.abs(ev.clientX - ultimo.x) < 40 && Math.abs(ev.clientY - ultimo.y) < 40) {
          ultimo = null;
          window.parent.postMessage({ fonte: 'gasprice-app', tipo: 'telaCheia' }, '*');
        } else {
          ultimo = { t: agora, x: ev.clientX, y: ev.clientY };
        }
      }, true);
    })();
  </script>"""

PRECONEXAO = """
  <!-- O mapa depende de dois servidores: conecta já e pede os estilos (claro e escuro) enquanto o app carrega -->
  <link rel="preconnect" href="https://unpkg.com">
  <link rel="preconnect" href="https://tiles.openfreemap.org" crossorigin>
  <link rel="preload" href="https://tiles.openfreemap.org/styles/positron" as="fetch" crossorigin>
  <link rel="preload" href="https://tiles.openfreemap.org/styles/dark" as="fetch" crossorigin>"""

DENSIDADE_MAPA = """
  <script>
    // O MapLibre fixa a densidade ao criar o mapa; aqui ele relê a cada redimensionamento. Como o app desenha
    // reduzido pela escala do aparelho, o mapa também: densidade × escala (1:1 com a tela, nítido)
    (function () {
      if (window.parent === window || !window.maplibregl) return;
      var p = maplibregl.Map.prototype, redimensionar = p.resize, Original = maplibregl.Map;
      window.__mapasDemo = [];
      // No toque, o duplo toque é da tela cheia (a página): com o zoom do mapa junto, ele baixava e desenhava blocos
      // no meio da animação de abrir (engasgava) e a tela cheia abria com o mapa ampliado. O plugin do Flutter religa
      // os gestos depois de criar o mapa: o religar deste fica sem efeito.
      var toque = window.matchMedia('(pointer: coarse)').matches;
      function semZoomDuplo(m) {
        if (!toque || m.__semZoomDuplo) return;
        try { m.doubleClickZoom.disable(); m.doubleClickZoom.enable = function () {}; m.__semZoomDuplo = true; } catch (e) {}
      }
      // já nasce na densidade certa (o plugin cria o mapa por maplibregl.Map)
      maplibregl.Map = function (opcoes) {
        var o = Object.assign({}, opcoes, { pixelRatio: window.devicePixelRatio * (window.__escalaApp || 1) });
        var mapa = new Original(o);
        if (window.__mapasDemo.indexOf(mapa) < 0) window.__mapasDemo.push(mapa);
        semZoomDuplo(mapa);
        // primeiro desenho completo do mapa (estilo, pedaços e pinos): a página mostra o app a partir daí
        // Pronto = mapa base carregado e os pinos dos postos já na tela (antes disso, a página mostraria o app pela
        // metade, um passo atrás da prévia). Reserva: 5 s depois de carregar, para uma área sem postos.
        var avisou = false, avisar = function () {
          if (avisou || window.parent === window) return;
          avisou = true;
          mapa.off('idle', conferir);
          window.parent.postMessage({ fonte: 'gasprice-app', tipo: 'mapaPronto' }, '*');
        };
        var conferir = function () {
          try {
            if (mapa.areTilesLoaded() && mapa.getLayer('gasprice-postos') &&
                mapa.queryRenderedFeatures({ layers: ['gasprice-postos'] }).length) setTimeout(avisar, 250);
          } catch (e) {}
        };
        mapa.on('idle', conferir);
        mapa.once('load', function () { setTimeout(avisar, 5000); });
        return mapa;
      };
      maplibregl.Map.prototype = p;
      p.resize = function () {
        if (window.__mapasDemo.indexOf(this) < 0) window.__mapasDemo.push(this);
        semZoomDuplo(this);
        var densidade = window.devicePixelRatio * (window.__escalaApp || 1);
        // MapLibre 5: a densidade muda por setPixelRatio (o campo antigo não é mais lido); ele mesmo refaz o tamanho
        if (typeof this.setPixelRatio === 'function') {
          if (Math.abs(this.getPixelRatio() - densidade) > 0.001) this.setPixelRatio(densidade);
        } else {
          this._pixelRatio = densidade;
        }
        return redimensionar.apply(this, arguments);
      };
      // Reserva: no celular, o aviso de que o mapa mudou de tamanho às vezes se perde (no giro do tablet, por
      // exemplo) e a imagem fica com o tamanho antigo, esticada. Se a imagem não bate com a área, refaz no tamanho
      setInterval(function () {
        window.__mapasDemo.forEach(function (m) {
          try {
            var k = m.getContainer(), c = m.getCanvas();
            if (!k.isConnected || !k.clientWidth || !k.clientHeight) return;
            var r = m.getPixelRatio();
            var alvo = window.devicePixelRatio * (window.__escalaApp || 1);
            if (Math.abs(r - alvo) > 0.001 && m.__densidadePedida !== alvo) {
              m.__densidadePedida = alvo;
              m.resize();
              return;
            }
            if (Math.abs(c.width - k.clientWidth * r) <= 2 && Math.abs(c.height - k.clientHeight * r) <= 2) {
              m.__ajustado = null;
              return;
            }
            // uma tentativa por tamanho de área: se o MapLibre limitar a imagem, não refaz sem parar
            var chave = k.clientWidth + 'x' + k.clientHeight + '@' + r;
            if (m.__ajustado === chave) return;
            m.__ajustado = chave;
            m.resize();
          } catch (e) {}
        });
      }, 400);
    })();
  </script>"""

LEIA_ME = """# Demonstração do GasPrice

Pasta gerada por `scripts/docs/gerar_demonstracao.py`. Vai para o GitHub: a Vercel publica esta pasta (`vercel.json`
na raiz do repositório).

- `index.html` e `assets/`: a página da demonstração (aparelho em 3D que se abre de celular em tablet e painel ao vivo).
- `app/`: o app em Flutter web, no modo demonstração (dados fictícios, sem servidor).
- `previa/`: a primeira tela do app em imagem (tema claro e escuro), mostrada nos aparelhos enquanto o app carrega.

## Publicar no portfólio

Copie a pasta inteira para o site, em qualquer caminho (por exemplo `/projetos/gasprice/`).
Ela só tem arquivos estáticos: serve em qualquer hospedagem (GitHub Pages, Netlify, Vercel, servidor próprio).

- Abra pelo endereço `.../index.html` ou `.../` servido pelo site. Aberto direto do disco (`file://`),
  o navegador bloqueia o app.
- Para testar no computador: `py -3 -m http.server 8000` dentro desta pasta e abra http://localhost:8000.
- O mapa usa os blocos do OpenFreeMap pela internet e precisa de WebGL no navegador.

Para gerar de novo depois de mudar o app: `py -3.12 scripts/docs/gerar_demonstracao.py`.
"""


def versionar() -> None:
    """Os arquivos do Flutter não têm hash no nome (main.dart.js, flutter_bootstrap.js, index.html): sem isto o
    navegador pode seguir abrindo o app antigo depois de uma build nova. A versão é o hash do main.dart.js e entra
    em todos os endereços da cadeia: página → app/index.html → flutter_bootstrap.js → main.dart.js."""
    v = hashlib.sha256((DESTINO / "app" / "main.dart.js").read_bytes()).hexdigest()[:10]
    trocas = {
        DESTINO / "app" / "index.html": [('src="flutter_bootstrap.js"', f'src="flutter_bootstrap.js?v={v}"')],
        DESTINO / "app" / "flutter_bootstrap.js": [('"mainJsPath":"main.dart.js"', f'"mainJsPath":"main.dart.js?v={v}"')],
        DESTINO / "index.html": [
            ('href="app/flutter_bootstrap.js"', f'href="app/flutter_bootstrap.js?v={v}"'),
            ('href="app/main.dart.js"', f'href="app/main.dart.js?v={v}"'),
            ("</head>", f'<meta name="versao-app" content="{v}">\n</head>'),
        ],
    }
    for arquivo, pares in trocas.items():
        texto = arquivo.read_text(encoding="utf-8")
        for antes, depois in pares:
            if antes not in texto:
                raise SystemExit(f"{arquivo.name}: não achei {antes!r} para pôr a versão do app")
            texto = texto.replace(antes, depois, 1)
        arquivo.write_text(texto, encoding="utf-8")
    print(f"versão do app: {v}")
    return v


# Área do app na tela de cada aparelho, em dp (palco.js, APARELHOS: tela menos as barras de status e de gestos), e a
# densidade da imagem (o bastante para o tamanho em que o aparelho aparece, sem pesar no primeiro carregamento)
PREVIAS = {
    "celular-retrato": (412, 891 - 32 - 20, 2),
    "tablet-deitado": (1480, 924 - 28 - 24, 1.25),
    "tablet-empe": (924, 1480 - 28 - 24, 1.5),
}
# O app dentro de um iframe, como na página (os ajustes da demonstração só valem dentro de uma moldura); avisa
# quando o mapa ficou pronto (com os pinos) e dá um tempo para os nomes assentarem
MOLDURA_PREVIA = """<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;overflow:hidden}iframe{border:0;display:block;width:100vw;height:100vh}</style>
<iframe id="app"></iframe>
<script>
  const q = new URLSearchParams(location.search);
  document.getElementById('app').src = 'app/?dpr=' + q.get('dpr') + '&escala=1&v=' + q.get('v');
  addEventListener('message', e => { if (e.data && e.data.tipo === 'mapaPronto') setTimeout(() => { document.title = 'pronto'; }, 1500); });
</script>"""
WEBP = """async b64 => { const i = new Image(); i.src = 'data:image/png;base64,' + b64; await i.decode();
  const c = document.createElement('canvas'); c.width = i.width; c.height = i.height; c.getContext('2d').drawImage(i, 0, 0);
  return c.toDataURL('image/webp', 0.8).split(',')[1]; }"""


def gerar_previas(v: str) -> None:
    """A primeira tela do app em imagem, para os aparelhos não ficarem só no ícone de carregamento enquanto o app
    (uns 3 MB de motor Flutter) baixa e compila: a página mostra a imagem e troca pelo app de verdade quando ele fica
    pronto. Usa o Playwright e a internet (blocos do mapa); sem eles, a página segue com o ícone."""
    import base64
    import functools
    import threading
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("Sem o Playwright: as prévias não foram geradas (a página mostra o ícone de carregamento)")
        return

    class Silencioso(SimpleHTTPRequestHandler):
        def log_message(self, *_):
            pass

    moldura = DESTINO / "_previa.html"
    moldura.write_text(MOLDURA_PREVIA, encoding="utf-8")
    pasta = DESTINO / "previa"
    pasta.mkdir(exist_ok=True)
    servidor = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Silencioso, directory=str(DESTINO)))
    threading.Thread(target=servidor.serve_forever, daemon=True).start()
    try:
        with sync_playwright() as p:
            try:
                navegador = p.chromium.launch()
            except Exception:
                navegador = p.chromium.launch(channel="msedge")
            for tema, esquema in (("claro", "light"), ("escuro", "dark")):
                for nome, (largura, altura, densidade) in PREVIAS.items():
                    ctx = navegador.new_context(viewport={"width": largura, "height": altura}, device_scale_factor=densidade,
                                                color_scheme=esquema)
                    pg = ctx.new_page()
                    pg.goto(f"http://127.0.0.1:{servidor.server_address[1]}/_previa.html?dpr={densidade}&v={v}")
                    pg.wait_for_function("document.title === 'pronto'", timeout=90000)
                    webp = pg.evaluate(WEBP, base64.b64encode(pg.screenshot()).decode())
                    (pasta / f"{nome}-{tema}.webp").write_bytes(base64.b64decode(webp))
                    ctx.close()
            navegador.close()
        print("prévias: " + ", ".join(f"{a.name} ({a.stat().st_size // 1024} KB)" for a in sorted(pasta.glob("*.webp"))))
    except Exception as e:
        print(f"Prévias não geradas ({e}); a página mostra o ícone de carregamento")
    finally:
        servidor.shutdown()
        moldura.unlink(missing_ok=True)


def adiantar_previas(v: str) -> None:
    """As prévias que aparecem primeiro (celular em pé e tablet deitado) começam a baixar com a página, só as do tema
    de quem visita; o endereço (com ?v) é o mesmo que palco.js pede."""
    links = [
        f'<link rel="preload" as="image" href="previa/{nome}-{tema}.webp?v={v}" media="(prefers-color-scheme: {esquema})">'
        for nome in ("celular-retrato", "tablet-deitado")
        for tema, esquema in (("claro", "light"), ("escuro", "dark"))
        if (DESTINO / "previa" / f"{nome}-{tema}.webp").exists()
    ]
    if links:
        indice = DESTINO / "index.html"
        indice.write_text(indice.read_text(encoding="utf-8").replace("</head>", "\n".join(links) + "\n</head>", 1), encoding="utf-8")


def main() -> int:
    if "--sem-build" not in sys.argv:
        cmd = [str(FLUTTER), "build", "web", "--release", "--no-wasm-dry-run", "--dart-define=DEMO=true",
               "--dart-define=DEMO_LOGADO=true", "--dart-define=SEM_FAIXA_DEMO=true", "--output", str(BUILD)]
        print(" ".join(cmd), flush=True)
        subprocess.run(cmd, cwd=APP, check=True)

    # Recria só app/: a raiz pode estar aberta num terminal (servidor local), o que impede apagá-la no Windows
    DESTINO.mkdir(exist_ok=True)
    if (DESTINO / "app").exists():
        shutil.rmtree(DESTINO / "app")
    # Fora: símbolos de depuração e o motor skwasm, que só é usado em builds WebAssembly (esta é em JavaScript)
    shutil.copytree(BUILD, DESTINO / "app", ignore=shutil.ignore_patterns("*.symbols", "skwasm*"))
    indice = DESTINO / "app" / "index.html"
    html = indice.read_text(encoding="utf-8")
    mapa = re.search(r'<script src="[^"]*maplibre-gl\.js"></script>', html)
    if '<base href="/">' not in html or "<head>" not in html or not mapa:
        print("O index.html do app não tem o formato esperado (base href, <head> ou script do MapLibre)")
        return 1
    # Endereço relativo: a pasta funciona em qualquer caminho do site (o app usa rotas com #)
    html = html.replace('<base href="/">', '<base href="./">')
    html = html.replace("<title>gasprice</title>", "<title>GasPrice · demonstração</title>")
    html = html.replace(mapa.group(0), mapa.group(0) + DENSIDADE_MAPA, 1)
    html = html.replace("<head>", "<head>" + PRECONEXAO + DENSIDADE, 1)
    indice.write_text(html, encoding="utf-8")

    # Página (React + Tailwind + three.js): dependências e build pelo Deno; o resultado vai ao lado de app/
    subprocess.run([str(DENO), "install"], cwd=PAGINA, check=True)
    subprocess.run([str(DENO), "task", "build"], cwd=PAGINA, check=True)
    if (DESTINO / "assets").exists():
        shutil.rmtree(DESTINO / "assets")
    shutil.copytree(PAGINA / "dist", DESTINO, dirs_exist_ok=True)
    v = versionar()
    if "--sem-previas" not in sys.argv:
        gerar_previas(v)
    adiantar_previas(v)
    endereco_mapa = re.search(r'src="([^"]+)"', mapa.group(0)).group(1)
    if endereco_mapa not in (DESTINO / "index.html").read_text(encoding="utf-8"):
        print(f"Aviso: a página não adianta o {endereco_mapa} (atualize o prefetch em demonstracao_web/index.html)")
    (DESTINO / "LEIA-ME.md").write_text(LEIA_ME, encoding="utf-8")

    total = sum(f.stat().st_size for f in DESTINO.rglob("*") if f.is_file())
    print(f"{DESTINO} ({total / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
