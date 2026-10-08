import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre/maplibre.dart'
    show
        CameraChangeReason,
        Geographic,
        MapController,
        MapEvent,
        MapEventCameraIdle,
        MapEventClick,
        MapEventStartMoveCamera,
        MapGestures,
        MapLibreMap,
        MapOptions,
        Marker,
        WidgetLayer;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/localizacao.dart';
import '../../servicos/preferencias.dart';
import '../../tema.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';
import '../../widgets/seletor_produto.dart';

/// Tela inicial: mapa do OpenFreeMap com os postos da área visível e o preço do combustível escolhido.
/// O mapa é vetorial (MapLibre), segue o tema claro ou escuro do celular e não usa chave de API.
/// O OpenFreeMap e o OpenStreetMap exigem os créditos visíveis no mapa.
class TelaMapa extends StatefulWidget {
  const TelaMapa({super.key});
  @override
  State<TelaMapa> createState() => _TelaMapaState();
}

class _TelaMapaState extends State<TelaMapa> {
  // Zoom do MapLibre (mundo de 512 px no zoom 0): um nível abaixo do mesmo enquadramento no OpenStreetMap raster
  static const _brasil = Geographic(lon: -47.88, lat: -15.79);
  static const _zoomBrasil = 3.2;
  static const _zoomMinimo = 10.0;
  static const _zoomLocal = 12.0;
  static const _estiloClaro = 'https://tiles.openfreemap.org/styles/positron';
  static const _estiloEscuro = 'https://tiles.openfreemap.org/styles/dark';

  /// Nos testes de widget não existe mapa nativo: a tela desenha os pinos lado a lado sobre um fundo liso.
  static final _semMapaNativo = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  MapController? _mapa;
  MapOptions? _opcoes;
  String? _estilo;
  List<PostoResumo> _postos = [];
  PostoResumo? _selecionado;
  bool _carregando = false;
  bool _longeDemais = false;
  bool _creditosAbertos = true;
  String? _erro;
  Timer? _espera;
  Timer? _vigia;
  String? _areaPedida;
  int _pedidos = 0;

  @override
  void initState() {
    super.initState();
    Preferencias.produto.addListener(_redesenhar);
    Localizacao.instancia.addListener(_redesenhar);
    if (_semMapaNativo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _iniciar());
    } else {
      // Se o mapa nativo não for criado, a tela avisa em vez de ficar vazia sem explicação
      _vigia = Timer(const Duration(seconds: 15), () {
        if (mounted && _mapa == null) setState(() => _erro = 'Não foi possível carregar o mapa.');
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final estilo = Theme.of(context).brightness == Brightness.dark ? _estiloEscuro : _estiloClaro;
    if (_estilo != null && estilo != _estilo) _mapa?.setStyle(estilo);
    _estilo = estilo;
  }

  @override
  void dispose() {
    Preferencias.produto.removeListener(_redesenhar);
    Localizacao.instancia.removeListener(_redesenhar);
    _espera?.cancel();
    _vigia?.cancel();
    super.dispose();
  }

  void _redesenhar() {
    if (mounted) setState(() {});
  }

  MapOptions _criarOpcoes() {
    final pos = Localizacao.instancia.atual;
    return MapOptions(
      initStyle: _estilo ?? _estiloClaro,
      initCenter: pos == null ? _brasil : Geographic(lon: pos.longitude, lat: pos.latitude),
      initZoom: pos == null ? _zoomBrasil : _zoomLocal,
      minZoom: 2,
      maxZoom: 19,
      // Norte sempre para cima e sem inclinação: os pinos ficam retos e a área carregada é um retângulo
      gestures: const MapGestures(rotate: false, pan: true, zoom: true, pitch: false),
      androidForegroundLoadColor: Theme.of(context).colorScheme.surface,
    );
  }

  void _aoCriar(MapController mapa) {
    _mapa = mapa;
    _vigia?.cancel();
    if (_erro != null) setState(() => _erro = null);
    // O tema pode ter mudado entre a criação das opções e a do mapa
    if (_estilo != null && _estilo != _opcoes?.initStyle) mapa.setStyle(_estilo!);
    _iniciar();
  }

  void _aoEvento(MapEvent e) {
    switch (e) {
      case MapEventStartMoveCamera(reason: CameraChangeReason.apiGesture) when _creditosAbertos:
        setState(() => _creditosAbertos = false);
      case MapEventCameraIdle():
        _espera?.cancel();
        _espera = Timer(const Duration(milliseconds: 250), _carregarArea);
      case MapEventClick():
        if (_selecionado != null) setState(() => _selecionado = null);
      default:
        break;
    }
  }

  Future<void> _iniciar() async {
    final salvos = await Api.instancia.ultimaAreaSalva();
    if (salvos.isNotEmpty && mounted && _postos.isEmpty) setState(() => _postos = salvos);
    final pos = await Localizacao.instancia.obter(pedirPermissao: false);
    if (!mounted) return;
    final mapa = _mapa;
    if (mapa != null) {
      // Também sem posição: na web os pinos só aparecem depois do primeiro movimento da câmera
      await mapa.moveCamera(
        center: pos == null ? mapa.getCamera().center : Geographic(lon: pos.longitude, lat: pos.latitude),
        zoom: pos == null ? null : _zoomLocal,
      );
    }
    _carregarArea();
  }

  /// Anima a câmera. Um gesto do usuário durante a animação a cancela, e isso não é erro.
  Future<void> _irPara(Geographic centro, {double? zoom}) async {
    try {
      await _mapa?.animateCamera(center: centro, zoom: zoom, nativeDuration: const Duration(milliseconds: 700));
    } catch (_) {}
  }

  Future<void> _centralizar() async {
    final pos = await Localizacao.instancia.obter();
    if (!mounted) return;
    if (pos == null) {
      mostrarMensagem(
        context,
        Localizacao.instancia.estado == EstadoLocalizacao.desligada
            ? 'Ative a localização do aparelho para ver os postos perto de você.'
            : 'Permita o acesso à localização nas configurações do app.',
      );
      return;
    }
    await _irPara(Geographic(lon: pos.longitude, lat: pos.latitude), zoom: _zoomLocal);
  }

  /// Zoom e limites da área visível. Sem mapa nativo (testes), uma área fixa de uns 25 km em volta da posição.
  ({double zoom, double sul, double oeste, double norte, double leste})? _areaVisivel() {
    if (_semMapaNativo) {
      final pos = Localizacao.instancia.atual;
      final lat = pos?.latitude ?? _brasil.lat, lon = pos?.longitude ?? _brasil.lon;
      return (zoom: _zoomLocal, sul: lat - 0.12, oeste: lon - 0.12, norte: lat + 0.12, leste: lon + 0.12);
    }
    final mapa = _mapa;
    if (mapa == null) return null;
    final r = mapa.getVisibleRegion();
    return (
      zoom: mapa.getCamera().zoom,
      sul: r.latitudeSouth,
      oeste: r.longitudeWest,
      norte: r.latitudeNorth,
      leste: r.longitudeEast,
    );
  }

  Future<void> _carregarArea() async {
    if (!mounted || (!Config.configurado && !Config.demo)) return;
    final area = _areaVisivel();
    if (area == null) return;
    if (area.zoom < _zoomMinimo) {
      setState(() => _longeDemais = true);
      return;
    }
    // O fim de um movimento e a abertura da tela podem pedir a mesma área ao mesmo tempo
    final chave = [area.sul, area.oeste, area.norte, area.leste].map((v) => (v * 50).round()).join(':');
    if (_carregando && chave == _areaPedida) return;
    _areaPedida = chave;
    final pedido = ++_pedidos;
    setState(() {
      _longeDemais = false;
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await Api.instancia.postosNaArea(area.sul, area.oeste, area.norte, area.leste);
      // Uma área mais nova foi pedida enquanto esta carregava: a resposta antiga é descartada
      if (pedido != _pedidos) return;
      final loc = Localizacao.instancia;
      _postos = lista.map((p) => p.comDistancia(loc.distanciaKm(p.lat, p.lon))).toList();
    } catch (e) {
      if (pedido == _pedidos) _erro = e.toString();
    } finally {
      if (mounted && pedido == _pedidos) setState(() => _carregando = false);
    }
  }

  void _selecionar(PostoResumo p, {bool mover = true}) {
    setState(() => _selecionado = p);
    if (mover && p.lat != null) _irPara(Geographic(lon: p.lon!, lat: p.lat!));
  }

  List<PostoResumo> get _ordenadosPorPreco {
    final produto = Preferencias.produto.value;
    final l = [..._postos];
    l.sort((a, b) {
      final pa = a.preco(produto)?.preco, pb = b.preco(produto)?.preco;
      if (pa == null && pb == null) return (a.distanciaKm ?? 999).compareTo(b.distanciaKm ?? 999);
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pa.compareTo(pb);
    });
    return l;
  }

  List<Marker> _marcadores() {
    final produto = Preferencias.produto.value;
    final visiveis = _longeDemais ? <PostoResumo>[] : _postos.where((p) => p.lat != null && p.lon != null).toList();
    // Postos com preço por cima dos sem preço, e o selecionado por cima de todos
    int camada(PostoResumo p) => p.id == _selecionado?.id ? 2 : (p.preco(produto) == null ? 0 : 1);
    visiveis.sort((a, b) => camada(a).compareTo(camada(b)));
    final pos = Localizacao.instancia.atual;
    return [
      for (final p in visiveis)
        Marker(
          point: Geographic(lon: p.lon!, lat: p.lat!),
          size: const Size(110, 44),
          // A ponta do pino marca o posto
          alignment: Alignment.bottomCenter,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _PinoPreco(
              posto: p,
              preco: p.preco(produto),
              selecionado: _selecionado?.id == p.id,
              aoTocar: () => _selecionar(p, mover: false),
            ),
          ),
        ),
      if (pos != null)
        Marker(point: Geographic(lon: pos.longitude, lat: pos.latitude), size: const Size(22, 22), child: const _PontoUsuario()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final expandido = tamanhoDe(context) == Tamanho.expandido;
    final cartaoAberto = _selecionado != null && !expandido;
    final marcadores = _marcadores();

    final mapa = Stack(children: [
      if (_semMapaNativo)
        Positioned.fill(child: _MapaDeTeste(marcadores: marcadores))
      else
        MapLibreMap(
          // Criadas uma vez: opções novas a cada quadro fariam o mapa reaplicar zoom e gestos
          options: _opcoes ??= _criarOpcoes(),
          onMapCreated: _aoCriar,
          onEvent: _aoEvento,
          children: [WidgetLayer(allowInteraction: true, markers: marcadores)],
        ),
      Positioned(
        left: 8,
        right: 88,
        bottom: cartaoAberto ? 220 : 8,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: _sobreOMapa(_Creditos(
            abertos: _creditosAbertos,
            aoAlternar: () => setState(() => _creditosAbertos = !_creditosAbertos),
          )),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _sobreOMapa(Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(28),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => context.go('/buscar'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      const Icon(Icons.search),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Buscar posto, endereço ou cidade',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                      if (_carregando) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ]),
                  ),
                ),
              ),
            )),
            _sobreOMapa(const SeletorProduto(sobreMapa: true)),
            if (!Config.configurado && !Config.demo)
              _sobreOMapa(const _Aviso('App sem conexão configurada com o Supabase. Veja o README.')),
            if (_longeDemais) _sobreOMapa(const _Aviso('Aproxime o mapa para ver os postos e preços.')),
            if (_erro != null) _sobreOMapa(_Aviso(_erro!)),
          ]),
        ),
      ),
      Positioned(
        right: 16,
        bottom: cartaoAberto ? 228 : 16,
        child: _sobreOMapa(FloatingActionButton(
          heroTag: 'centralizar',
          tooltip: 'Minha localização',
          onPressed: _centralizar,
          child: const Icon(Icons.my_location),
        )),
      ),
      if (cartaoAberto)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _sobreOMapa(_CartaoSelecionado(posto: _selecionado!, produtoId: Preferencias.produto.value)),
        ),
    ]);

    return Scaffold(
      body: expandido
          ? Row(children: [
              Expanded(child: mapa),
              SizedBox(
                width: 380,
                child: _ListaLateral(
                  postos: _ordenadosPorPreco,
                  selecionado: _selecionado,
                  aoSelecionar: _selecionar,
                  longeDemais: _longeDemais,
                ),
              ),
            ])
          : mapa,
    );
  }
}

/// Na web, o mapa é um elemento HTML que capturaria os toques nos controles desenhados por cima dele.
Widget _sobreOMapa(Widget filho) => PointerInterceptor(intercepting: kIsWeb, child: filho);

enum _EstiloPino { cheio, contorno, tracejado, vazio }

/// Pino com o preço. Até 7 dias: preenchido, com o número em branco. Preço velho, estimativa e posto sem preço:
/// contorno (tracejado na estimativa), para que a idade do dado não dependa só da cor.
class _PinoPreco extends StatelessWidget {
  final PostoResumo posto;
  final PrecoAtual? preco;
  final bool selecionado;
  final VoidCallback aoTocar;
  const _PinoPreco({required this.posto, required this.preco, required this.selecionado, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final p = preco;
    final cores = Tema.cores(context);
    // Os pinos preenchidos usam os tons do tema claro também no escuro: ficam sobre o mapa, com o número em branco
    final (estilo, cor) = p == null
        ? (_EstiloPino.vazio, cores.semPreco)
        : p.fonte == FontePreco.estimativa
            ? (_EstiloPino.tracejado, cores.estimativa)
            : switch (p.frescor()) {
                Frescor.recente => (_EstiloPino.cheio, CoresPreco.claro.recente),
                Frescor.antigo => (_EstiloPino.cheio, CoresPreco.claro.antigo),
                Frescor.semAtualizacao => (_EstiloPino.contorno, cores.semAtualizacao),
              };
    final cheio = estilo == _EstiloPino.cheio;
    final corTexto = cheio ? Colors.white : cor;
    final borda = switch (estilo) {
      _EstiloPino.cheio => Colors.white,
      _EstiloPino.vazio => cores.bordaSemPreco,
      // Tracejado: a borda contínua fica transparente, com a mesma largura, e o traço é desenhado por cima
      _EstiloPino.tracejado => Colors.transparent,
      _EstiloPino.contorno => cor,
    };
    final larguraBorda = cheio || estilo == _EstiloPino.vazio ? 1.5 : 2.0;
    final texto = p == null
        ? '–'
        : (p.fonte == FontePreco.estimativa ? '≈${preco_(p.preco)}' : preco_(p.preco)).replaceAll('R\$ ', '').replaceAll('R\$', '');
    final rotulo = (p == null
            ? '${posto.nome}, sem preço'
            : '${posto.nome}, ${preco_(p.preco)}${p.fonte == FontePreco.estimativa ? ', estimativa' : ''}') +
        (posto.precisao.aproximada ? ', localização aproximada' : '');
    // O marcador do mapa tem tamanho fixo: a fonte do pino cresce no máximo 15%
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Semantics(
        button: true,
        label: rotulo,
        child: GestureDetector(
          onTap: aoTocar,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(
              foregroundPainter: estilo == _EstiloPino.tracejado ? _BordaTracejada(cor) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: cheio ? cor : cores.fundoPino,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: borda, width: larguraBorda),
                  boxShadow: [
                    const BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
                    // Selecionado: anel na cor do texto do tema, por fora da borda
                    if (selecionado) BoxShadow(color: Theme.of(context).colorScheme.onSurface, spreadRadius: 2.5),
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (posto.precisao.aproximada) ...[
                    Icon(Icons.location_searching, size: 13, color: corTexto),
                    const SizedBox(width: 3),
                  ],
                  Text(texto,
                      style: TextStyle(
                        color: corTexto,
                        fontWeight: estilo == _EstiloPino.vazio ? FontWeight.w700 : FontWeight.w800,
                        fontSize: 13,
                        height: 1.1,
                      )),
                ]),
              ),
            ),
            CustomPaint(size: const Size(12, 7), painter: _Ponta(estilo == _EstiloPino.vazio ? cores.bordaSemPreco : cor)),
          ]),
        ),
      ),
    );
  }
}

class _Ponta extends CustomPainter {
  final Color cor;
  const _Ponta(this.cor);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = cor);
  }

  @override
  bool shouldRepaint(_Ponta old) => old.cor != cor;
}

/// Contorno tracejado do pino de estimativa, sobre a borda transparente de 2 px.
class _BordaTracejada extends CustomPainter {
  final Color cor;
  const _BordaTracejada(this.cor);
  @override
  void paint(Canvas canvas, Size size) {
    final contorno = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)).deflate(1));
    final tinta = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final trecho in contorno.computeMetrics()) {
      for (var d = 0.0; d < trecho.length; d += 8) {
        canvas.drawPath(trecho.extractPath(d, d + 5), tinta);
      }
    }
  }

  @override
  bool shouldRepaint(_BordaTracejada old) => old.cor != cor;
}

class _PontoUsuario extends StatelessWidget {
  const _PontoUsuario();
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Sua localização',
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A73E8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x551A73E8), blurRadius: 8, spreadRadius: 4)],
          ),
        ),
      );
}

/// Créditos exigidos pelo OpenFreeMap e pela licença do OpenStreetMap. Começam abertos e recolhem no primeiro
/// gesto no mapa; o botão de informação abre de novo.
class _Creditos extends StatelessWidget {
  final bool abertos;
  final VoidCallback aoAlternar;
  const _Creditos({required this.abertos, required this.aoAlternar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final estilo = Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    Widget link(String texto, String endereco) => InkWell(
          onTap: () => launchUrl(Uri.parse(endereco)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(texto, style: estilo?.copyWith(decoration: TextDecoration.underline)),
          ),
        );
    return Material(
      color: cs.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (abertos)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                link('OpenFreeMap', 'https://openfreemap.org'),
                link('© OpenMapTiles', 'https://www.openmaptiles.org/'),
                link('© colaboradores do OpenStreetMap', 'https://www.openstreetmap.org/copyright'),
              ]),
            ),
          ),
        IconButton(
          tooltip: abertos ? 'Ocultar créditos do mapa' : 'Créditos do mapa',
          icon: Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
          onPressed: aoAlternar,
        ),
      ]),
    );
  }
}

/// Usado só nos testes de widget, onde não há mapa nativo. Cada pino fica na caixa de tamanho fixo que teria no
/// mapa, para a auditoria de telas continuar medindo o pino com fonte ampliada.
class _MapaDeTeste extends StatelessWidget {
  final List<Marker> marcadores;
  const _MapaDeTeste({required this.marcadores});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
            for (final m in marcadores) SizedBox.fromSize(size: m.size, child: m.child),
          ]),
        ),
      );
}

class _Aviso extends StatelessWidget {
  final String texto;
  const _Aviso(this.texto);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: Theme.of(context).colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(texto, style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface)),
          ),
        ),
      );
}

class _CartaoSelecionado extends StatelessWidget {
  final PostoResumo posto;
  final int produtoId;
  const _CartaoSelecionado({required this.posto, required this.produtoId});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    const altura = Size(0, 48);
    // Um só cartão: o resumo do posto perde a borda e o fundo próprios e divide a superfície com os botões
    return Material(
      elevation: 6,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Theme(
          data: tema.copyWith(
            cardTheme: tema.cardTheme.copyWith(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          child: CartaoPosto(posto: posto, produtoId: produtoId, aoTocar: () => context.push('/posto/${posto.id}')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: altura,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => context.push('/posto/${posto.id}/enviar'),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Atualizar preço'),
              ),
            ),
            const SizedBox(width: 8),
            // Ação principal no botão cheio da marca, como nas outras telas
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: altura,
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                onPressed: () => context.push('/posto/${posto.id}'),
                child: const Text('Ver posto'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ListaLateral extends StatelessWidget {
  final List<PostoResumo> postos;
  final PostoResumo? selecionado;
  final void Function(PostoResumo) aoSelecionar;
  final bool longeDemais;
  const _ListaLateral({required this.postos, this.selecionado, required this.aoSelecionar, required this.longeDemais});

  @override
  Widget build(BuildContext context) {
    final produto = Preferencias.produto.value;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        left: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Postos nesta área · menor preço primeiro', style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: postos.isEmpty
                ? EstadoVazio(
                    icone: Icons.zoom_in_map,
                    titulo: longeDemais ? 'Aproxime o mapa' : 'Nenhum posto aqui',
                    texto: longeDemais ? 'Os postos aparecem a partir do nível de bairro.' : 'Mova o mapa para outra região.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: postos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => CartaoPosto(
                      posto: postos[i],
                      produtoId: produto,
                      selecionado: selecionado?.id == postos[i].id,
                      aoTocar: () => selecionado?.id == postos[i].id
                          ? context.push('/posto/${postos[i].id}')
                          : aoSelecionar(postos[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
