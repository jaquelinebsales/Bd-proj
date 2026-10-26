import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../modelos/modelos.dart';
import 'monitor_demo_saida.dart' if (dart.library.js_interop) 'monitor_demo_saida_web.dart' as saida;
import 'preferencias.dart';

/// Na demonstração web, conta à página que envolve o app o que acontece na tela e qual parte da
/// arquitetura cada ação usaria (camadas: app, ocr, api, funcao, banco). Fora da demonstração não faz nada.
class MonitorDemo {
  MonitorDemo._();

  static const _telas = {
    '/': 'Mapa',
    '/buscar': 'Busca',
    '/favoritos': 'Favoritos',
    '/perfil': 'Perfil',
    '/boas-vindas': 'Boas-vindas',
    '/posto/:id': 'Posto',
    '/posto/:id/historico': 'Histórico de preços',
    '/posto/:id/avaliacoes': 'Avaliações',
    '/posto/:id/avaliar': 'Avaliar posto',
    '/posto/:id/enviar': 'Atualizar preços',
    '/posto/:id/posicao': 'Estou neste posto',
    '/entrar': 'Entrar',
    '/cadastro': 'Cadastro',
    '/recuperar-senha': 'Recuperar senha',
    '/nova-senha': 'Nova senha',
    '/verificar-email': 'Verificar e-mail',
    // os nomes seguem o título que cada tela mostra
    '/perfil/editar': 'Alterar dados',
    '/perfil/senha': 'Alterar senha',
    '/perfil/envios': 'Preços enviados',
    '/perfil/avaliacoes': 'Minhas avaliações',
    '/pontos': 'Meus pontos',
    '/ranking': 'Ranking da comunidade',
    '/notificacoes': 'Notificações',
    '/sobre': 'Sobre os dados e privacidade',
  };

  static void iniciar(GoRouter rotas) {
    if (!Config.demo) return;
    saida.iniciarEscala();
    String? ultima;
    void rota() {
      var atual = rotas.routerDelegate.currentConfiguration;
      // Telas abertas com push (o posto, o histórico...) ficam numa lista própria dentro da última correspondência
      while (atual.isNotEmpty && atual.last is ImperativeRouteMatch) {
        atual = (atual.last as ImperativeRouteMatch).matches;
      }
      if (atual.isEmpty || atual.uri.toString() == ultima) return;
      ultima = atual.uri.toString();
      saida.enviar({'tipo': 'tela', 'nome': _telas[atual.fullPath] ?? atual.fullPath, 'rota': ultima});
    }

    rotas.routerDelegate.addListener(rota);
    rota();
    Preferencias.produto.addListener(() => evento('Combustível',
        detalhe: Preferencias.produto.value.map((id) => Produto.porId(id).nome).join(', ')));
    Preferencias.raioKm.addListener(() {
      final r = Preferencias.raioKm.value;
      evento('Raio', detalhe: r == null ? 'qualquer distância' : '${r.toStringAsFixed(0)} km');
    });
  }

  static void evento(String texto, {String? detalhe, List<String> camadas = const ['app']}) {
    if (!Config.demo) return;
    saida.enviar({'tipo': 'evento', 'texto': texto, 'detalhe': ?detalhe, 'camadas': camadas});
  }

  /// Envolve o app: a cada toque (não arrasto), descobre o rótulo do botão tocado e avisa a página.
  /// Assim todo botão, filtro e item de menu é coberto sem marcar um por um.
  static Widget envolver(Widget filho) {
    if (!Config.demo) return filho;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _inicio = e.position;
        _informado = false;
      },
      onPointerUp: _aoSoltar,
      child: _Escala(filho),
    );
  }

  /// Observador de um navegador (um por navegador: o raiz e cada aba). Quando fecha uma folha, menu ou diálogo,
  /// avisa a página, que volta a explicar a tela que ficou à vista.
  static NavigatorObserver observador() => _Observador();

  /// Para controles que mudam arrastando (o toque simples não os pega): avisa o valor a cada mudança.
  static void toque(String rotulo) {
    if (!Config.demo) return;
    _informado = true;
    saida.enviar({'tipo': 'toque', 'rotulo': rotulo});
  }

  static Offset? _inicio;
  // o controle já se informou neste gesto: o rótulo genérico do toque não deve sobrescrever
  static bool _informado = false;

  static void _aoSoltar(PointerUpEvent e) {
    final inicio = _inicio;
    _inicio = null;
    if (_informado || inicio == null || (e.position - inicio).distance > 12) return;
    final rotulo = _rotuloEm(e.position, e.viewId);
    if (rotulo != null) saida.enviar({'tipo': 'toque', 'rotulo': rotulo});
  }

  /// Do alvo mais específico para fora, o primeiro elemento pequeno (um botão, não a tela inteira) com rótulo legível
  static String? _rotuloEm(Offset posicao, int viewId) {
    final resultado = HitTestResult();
    RendererBinding.instance.hitTestInView(resultado, posicao, viewId);
    final views = RendererBinding.instance.renderViews;
    if (views.isEmpty) return null;
    // a área da tela no espaço do app (que desenha ampliado pela escala, ver _Escala)
    final k = saida.escalaAtual.value;
    final area = views.first.size.width * views.first.size.height / (k * k);
    for (final entrada in resultado.path) {
      final alvo = entrada.target;
      if (alvo is! RenderBox || !alvo.hasSize) continue;
      if (alvo.size.width * alvo.size.height > area * 0.2) break;
      final rotulo = _rotulo(alvo);
      if (rotulo != null) return rotulo;
    }
    return null;
  }

  static String? _rotulo(RenderObject raiz) {
    String? achado;
    void visitar(RenderObject o) {
      if (achado != null) return;
      if (o is RenderSemanticsAnnotations) {
        final l = o.properties.label ?? o.properties.tooltip;
        if (_legivel(l)) {
          achado = l!.trim();
          return;
        }
      }
      if (o is RenderParagraph) {
        final s = o.text.toPlainText();
        if (_legivel(s)) {
          achado = s.trim();
          return;
        }
      }
      o.visitChildren(visitar);
    }

    visitar(raiz);
    return achado;
  }

  /// Uma folha, menu ou lista fechou: a página volta a explicar a tela à vista
  static void fechou() {
    if (Config.demo) saida.enviar({'tipo': 'retorno'});
  }

  // Ignora textos vazios, longos e os que são só ícones (fontes de ícones ficam nas áreas de uso privado do
  // Unicode: U+E000–F8FF e, nos ícones arredondados, U+F0000 em diante)
  static bool _legivel(String? s) {
    if (s == null) return false;
    final t = s.trim();
    return t.isNotEmpty && t.length <= 80 && t.runes.any((r) => r < 0xE000 || (r > 0xF8FF && r < 0xF0000));
  }
}

/// Na demonstração, a página mostra o aparelho reduzido (escala k). Em vez de a página reduzir a imagem do app
/// (o que a deixa mole), o app desenha já reduzido: o layout continua o do aparelho real (por exemplo 412 dp de
/// largura), mas cada dp ocupa k pixels da tela, e textos e ícones saem nítidos, pixel a pixel.
class _Escala extends StatelessWidget {
  final Widget filho;
  const _Escala(this.filho);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: saida.escalaAtual,
        builder: (context, k, _) {
          if ((k - 1).abs() < 0.001) return filho;
          final mq = MediaQuery.of(context);
          final tamanho = mq.size / k;
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: tamanho.width,
              maxWidth: tamanho.width,
              minHeight: tamanho.height,
              maxHeight: tamanho.height,
              child: Transform.scale(
                scale: k,
                alignment: Alignment.topLeft,
                child: MediaQuery(
                  data: mq.copyWith(
                    size: tamanho,
                    devicePixelRatio: mq.devicePixelRatio * k,
                    padding: mq.padding / k,
                    viewPadding: mq.viewPadding / k,
                    viewInsets: mq.viewInsets / k,
                    systemGestureInsets: mq.systemGestureInsets / k,
                  ),
                  child: filho,
                ),
              ),
            ),
          );
        },
      );
}

class _Observador extends NavigatorObserver {
  // Folhas, menus e diálogos são PopupRoute; as telas (páginas do go_router) não
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) MonitorDemo.fechou();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) MonitorDemo.fechou();
  }
}
