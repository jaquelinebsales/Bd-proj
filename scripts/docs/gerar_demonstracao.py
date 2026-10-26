"""
Gera a pasta demonstracao/ (fora do Git): a demonstração web do app para o portfólio.

- demonstracao/app/: build web do modo demonstração, já logada como a usuária fictícia, sem servidor.
- demonstracao/index.html e assets/: a página (React, Tailwind e three.js, em scripts/docs/demonstracao_web), com o
  aparelho em 3D que se abre de celular em tablet e o painel que acompanha a arquitetura ao vivo.

O endereço base é relativo ("./"), então a pasta funciona em qualquer caminho do site.
A página é compilada com o Deno (dev-tools/deno), que roda o Vite sem precisar do Node.

Uso: py -3.12 scripts/docs/gerar_demonstracao.py [--sem-build]   (--sem-build: não recompila o Flutter)
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
      var busca = new URLSearchParams(location.search);
      var inicial = Number(busca.get('dpr'));
      var atual = inicial > 0 ? inicial : (window.devicePixelRatio || 1);
      Object.defineProperty(window, 'devicePixelRatio', { configurable: true, get: function () { return atual; } });
      // Escala em que o aparelho aparece na página: o app desenha já nesse tamanho (pixel a pixel, sem a página
      // reduzir a imagem dele), lendo window.__escalaApp (app/lib/servicos/monitor_demo_saida_web.dart)
      var escala = Number(busca.get('escala'));
      window.__escalaApp = escala > 0 ? escala : 1;
      try { localStorage.setItem('flutter.viu_boas_vindas', 'true'); } catch (e) {}
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
        // de volta da tela cheia: o mapa redesenha (escondido, o navegador pode ter descartado a imagem dele)
        if (d.tipo === 'reavivar') {
          redimensionar();
          (window.__mapasDemo || []).forEach(function (m) { try { m.triggerRepaint(); } catch (e) {} });
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
      // Duplo toque (dedo, dois toques curtos e parados no mesmo lugar): a página abre o app em tela cheia
      var inicio = null, ultimo = null;
      window.addEventListener('pointerdown', function (ev) {
        inicio = ev.pointerType === 'touch' ? { t: Date.now(), x: ev.clientX, y: ev.clientY } : null;
      }, true);
      window.addEventListener('pointerup', function (ev) {
        var agora = Date.now();
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

DENSIDADE_MAPA = """
  <script>
    // O MapLibre fixa a densidade ao criar o mapa; aqui ele relê a cada redimensionamento. Como o app desenha
    // reduzido pela escala do aparelho, o mapa também: densidade × escala (1:1 com a tela, nítido)
    (function () {
      if (window.parent === window || !window.maplibregl) return;
      var p = maplibregl.Map.prototype, redimensionar = p.resize, Original = maplibregl.Map;
      window.__mapasDemo = [];
      // já nasce na densidade certa (o plugin cria o mapa por maplibregl.Map)
      maplibregl.Map = function (opcoes) {
        var o = Object.assign({}, opcoes, { pixelRatio: window.devicePixelRatio * (window.__escalaApp || 1) });
        var mapa = new Original(o);
        window.__mapasDemo.push(mapa);
        return mapa;
      };
      maplibregl.Map.prototype = p;
      p.resize = function () {
        if (window.__mapasDemo.indexOf(this) < 0) window.__mapasDemo.push(this);
        this._pixelRatio = window.devicePixelRatio * (window.__escalaApp || 1);
        return redimensionar.apply(this, arguments);
      };
    })();
  </script>"""

LEIA_ME = """# Demonstração do GasPrice

Pasta gerada por `scripts/docs/gerar_demonstracao.py`. Não vai para o GitHub.

- `index.html` e `assets/`: a página da demonstração (aparelho em 3D que se abre de celular em tablet e painel ao vivo).
- `app/`: o app em Flutter web, no modo demonstração (dados fictícios, sem servidor).

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
    html = html.replace("<head>", "<head>" + DENSIDADE, 1)
    indice.write_text(html, encoding="utf-8")

    # Página (React + Tailwind + three.js): dependências e build pelo Deno; o resultado vai ao lado de app/
    subprocess.run([str(DENO), "install"], cwd=PAGINA, check=True)
    subprocess.run([str(DENO), "task", "build"], cwd=PAGINA, check=True)
    if (DESTINO / "assets").exists():
        shutil.rmtree(DESTINO / "assets")
    shutil.copytree(PAGINA / "dist", DESTINO, dirs_exist_ok=True)
    versionar()
    (DESTINO / "LEIA-ME.md").write_text(LEIA_ME, encoding="utf-8")

    total = sum(f.stat().st_size for f in DESTINO.rglob("*") if f.is_file())
    print(f"{DESTINO} ({total / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
