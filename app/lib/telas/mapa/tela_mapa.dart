import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre/maplibre.dart'
    show
        CameraChangeReason,
        CircleStyleLayer,
        FillStyleLayer,
        GeoJsonSource,
        Geographic,
        LineStyleLayer,
        LngLatBounds,
        MapController,
        MapEvent,
        MapEventCameraIdle,
        MapEventClick,
        MapEventStartMoveCamera,
        MapGestures,
        MapLibreMap,
        MapOptions,
        StyleController,
        SymbolStyleLayer;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/localizacao.dart';
import '../../servicos/preferencias.dart';
import '../../tema.dart';
import '../../util/diagnostico.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';
import '../../widgets/seletor_produto.dart';
import '../../widgets/seletor_raio.dart';
import 'pino.dart';

typedef _Area = ({double sul, double oeste, double norte, double leste});

const _geoVazio = '{"type":"FeatureCollection","features":[]}';

/// Retângulo que contém o círculo de [km] em volta do ponto.
_Area _caixa(double lat, double lon, double km) {
  final dLat = km / 111.32, dLon = km / (111.32 * math.cos(lat * math.pi / 180));
  return (sul: lat - dLat, oeste: lon - dLon, norte: lat + dLat, leste: lon + dLon);
}

String _circulo(double lat, double lon, double km) {
  final cos = math.cos(lat * math.pi / 180);
  final anel = [
    for (var i = 0; i <= 64; i++)
      [lon + km * math.cos(2 * math.pi * i / 64) / (111.32 * cos), lat + km * math.sin(2 * math.pi * i / 64) / 111.32],
  ];
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {'type': 'Feature', 'properties': <String, Object>{}, 'geometry': {'type': 'Polygon', 'coordinates': [anel]}},
    ],
  });
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

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
  String? _chavePedida;
  int _pedidos = 0;

  /// O que já está carregado: a chave da consulta e, fora do modo raio, a área com folga em volta da tela.
  String? _chaveCarregada;
  _Area? _areaCarregada;

  /// Estilo atual do mapa e as imagens de pino já registradas nele (uma por aparência).
  StyleController? _estiloMapa;
  Map<String, Future<void>> _imagens = {};
  int _desenhos = 0;
  Object? _desenhado;

  @override
  void initState() {
    super.initState();
    Preferencias.produto.addListener(_redesenhar);
    Preferencias.raioKm.addListener(_aoMudarRaio);
    Localizacao.instancia.addListener(_aoMudarLocalizacao);
    if (_semMapaNativo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _iniciar());
    } else {
      // Se o mapa nativo não for criado, a tela avisa em vez de ficar vazia sem explicação
      _vigia = Timer(const Duration(seconds: 15), () {
        if (mounted && _mapa == null) {
          final causa = Diagnostico.ultimoErro;
          setState(() => _erro = 'Não foi possível carregar o mapa.${causa == null ? '' : '\n$causa'}');
        }
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
    Preferencias.raioKm.removeListener(_aoMudarRaio);
    Localizacao.instancia.removeListener(_aoMudarLocalizacao);
    _espera?.cancel();
    _vigia?.cancel();
    super.dispose();
  }

  void _redesenhar() {
    if (mounted) setState(() {});
  }

  bool get _porRaio => Preferencias.raioKm.value != null && Localizacao.instancia.atual != null;

  void _aoMudarLocalizacao() {
    _redesenhar();
    if (_porRaio) _carregarArea();
  }

  Future<void> _aoMudarRaio() async {
    if (Preferencias.raioKm.value != null && Localizacao.instancia.atual == null) {
      final pos = await Localizacao.instancia.obter();
      if (!mounted) return;
      if (pos == null) {
        Preferencias.raioKm.value = null;
        mostrarMensagem(context, 'Permita o acesso à localização para ver os postos por distância.');
        return;
      }
    }
    // O posto aberto pode ter ficado fora do novo raio
    setState(() => _selecionado = null);
    if (_porRaio) unawaited(_enquadrarRaio());
    _carregarArea();
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

  /// Cada estilo novo (inclusive na troca de tema) chega sem as camadas do app: elas são criadas de novo.
  Future<void> _aoCarregarEstilo(StyleController estilo) async {
    _estiloMapa = estilo;
    _imagens = {};
    _desenhado = null;
    final marca = _hex(Theme.of(context).colorScheme.primary);
    try {
      for (final id in ['gasprice-raio', 'gasprice-usuario', CamadaPinos.fonte, CamadaPinos.idSelecionado]) {
        await estilo.addSource(GeoJsonSource(id: id, data: _geoVazio));
      }
      await estilo.addLayer(FillStyleLayer(
        id: 'gasprice-raio-area',
        sourceId: 'gasprice-raio',
        paint: {'fill-color': marca, 'fill-opacity': 0.08},
      ));
      await estilo.addLayer(LineStyleLayer(
        id: 'gasprice-raio-borda',
        sourceId: 'gasprice-raio',
        paint: {'line-color': marca, 'line-width': 2, 'line-opacity': 0.6},
      ));
      await estilo.addLayer(const CircleStyleLayer(
        id: 'gasprice-usuario-halo',
        sourceId: 'gasprice-usuario',
        paint: {'circle-radius': 14, 'circle-color': '#1A73E8', 'circle-opacity': 0.2},
      ));
      await estilo.addLayer(const CircleStyleLayer(
        id: 'gasprice-usuario',
        sourceId: 'gasprice-usuario',
        paint: {'circle-radius': 7, 'circle-color': '#1A73E8', 'circle-stroke-width': 3, 'circle-stroke-color': '#FFFFFF'},
      ));
      await estilo.addLayer(const SymbolStyleLayer(
        id: CamadaPinos.id,
        sourceId: CamadaPinos.fonte,
        layout: CamadaPinos.layout,
        paint: CamadaPinos.paint,
      ));
      await estilo.addLayer(const SymbolStyleLayer(
        id: CamadaPinos.idSelecionado,
        sourceId: CamadaPinos.idSelecionado,
        layout: CamadaPinos.layoutSelecionado,
        paint: CamadaPinos.paint,
      ));
    } catch (e) {
      // Na troca rápida de tema o estilo pode ser substituído no meio da criação
      if (estilo == _estiloMapa && mounted) setState(() => _erro = 'Não foi possível desenhar os postos no mapa.\n$e');
      return;
    }
    if (mounted) setState(() {});
  }

  void _aoEvento(MapEvent e) {
    switch (e) {
      case MapEventStartMoveCamera(reason: CameraChangeReason.apiGesture) when _creditosAbertos:
        setState(() => _creditosAbertos = false);
      case MapEventCameraIdle():
        _espera?.cancel();
        _espera = Timer(const Duration(milliseconds: 150), _carregarArea);
      case MapEventClick(:final screenPoint):
        _tocarNoMapa(screenPoint);
      default:
        break;
    }
  }

  void _tocarNoMapa(Offset ponto) {
    final tocados = _mapa?.featuresAtPoint(ponto, layerIds: [CamadaPinos.idSelecionado, CamadaPinos.id]) ?? const [];
    final id = tocados.isEmpty ? null : num.tryParse('${tocados.first.properties['id']}')?.toInt();
    final posto = id == null ? null : _postos.where((p) => p.id == id).firstOrNull;
    if (posto != null) {
      _selecionar(posto, mover: false);
    } else if (_selecionado != null) {
      setState(() => _selecionado = null);
    }
  }

  Future<void> _iniciar() async {
    final salvos = await Api.instancia.ultimaAreaSalva();
    if (salvos.isNotEmpty && mounted && _postos.isEmpty) setState(() => _postos = salvos);
    final pos = await Localizacao.instancia.obter(pedirPermissao: false);
    if (!mounted) return;
    final mapa = _mapa;
    if (mapa != null) {
      if (_porRaio) {
        await _enquadrarRaio(animar: false);
      } else {
        // Também sem posição: na web os pinos só aparecem depois do primeiro movimento da câmera
        await mapa.moveCamera(
          center: pos == null ? mapa.getCamera().center : Geographic(lon: pos.longitude, lat: pos.latitude),
          zoom: pos == null ? null : _zoomLocal,
        );
      }
    }
    _carregarArea();
  }

  /// Anima a câmera. Um gesto do usuário durante a animação a cancela, e isso não é erro.
  Future<void> _irPara(Geographic centro, {double? zoom}) async {
    try {
      await _mapa?.animateCamera(center: centro, zoom: zoom, nativeDuration: const Duration(milliseconds: 700));
    } catch (_) {}
  }

  /// Mostra o círculo inteiro do raio, abaixo da busca e dos filtros.
  Future<void> _enquadrarRaio({bool animar = true}) async {
    final raio = Preferencias.raioKm.value, pos = Localizacao.instancia.atual, mapa = _mapa;
    if (raio == null || pos == null || mapa == null) return;
    final c = _caixa(pos.latitude, pos.longitude, raio);
    try {
      await mapa.fitBounds(
        bounds: LngLatBounds(longitudeWest: c.oeste, longitudeEast: c.leste, latitudeSouth: c.sul, latitudeNorth: c.norte),
        padding: const EdgeInsets.fromLTRB(24, 190, 24, 24),
        nativeDuration: animar ? const Duration(milliseconds: 700) : Duration.zero,
      );
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
    if (_porRaio) {
      await _enquadrarRaio();
    } else {
      await _irPara(Geographic(lon: pos.longitude, lat: pos.latitude), zoom: _zoomLocal);
    }
  }

  /// Zoom e limites da área visível. Sem mapa nativo (testes), uma área fixa de uns 25 km em volta da posição.
  ({double zoom, _Area area})? _areaVisivel() {
    if (_semMapaNativo) {
      final pos = Localizacao.instancia.atual;
      final lat = pos?.latitude ?? _brasil.lat, lon = pos?.longitude ?? _brasil.lon;
      return (zoom: _zoomLocal, area: (sul: lat - 0.12, oeste: lon - 0.12, norte: lat + 0.12, leste: lon + 0.12));
    }
    final mapa = _mapa;
    if (mapa == null) return null;
    final r = mapa.getVisibleRegion();
    return (
      zoom: mapa.getCamera().zoom,
      area: (sul: r.latitudeSouth, oeste: r.longitudeWest, norte: r.latitudeNorth, leste: r.longitudeEast),
    );
  }

  /// Carrega os postos do raio em volta do usuário ou, sem raio, da área visível com uma folga de 25% em cada lado.
  /// Enquanto a tela continua dentro da área já carregada, mover o mapa não faz consulta nenhuma.
  Future<void> _carregarArea() async {
    if (!mounted || (!Config.configurado && !Config.demo)) return;
    final String chave;
    final Future<List<PostoResumo>> Function() consulta;
    _Area? area;
    final raio = Preferencias.raioKm.value, pos = Localizacao.instancia.atual;
    if (raio != null && pos != null) {
      if (_longeDemais) setState(() => _longeDemais = false);
      chave = 'raio:${pos.latitude.toStringAsFixed(3)}:${pos.longitude.toStringAsFixed(3)}:$raio';
      if (chave == _chaveCarregada) return;
      consulta = () => Api.instancia.postosProximos(pos.latitude, pos.longitude, raioKm: raio, limite: 500);
    } else {
      final visivel = _areaVisivel();
      if (visivel == null) return;
      if (visivel.zoom < _zoomMinimo) {
        if (!_longeDemais) setState(() => _longeDemais = true);
        return;
      }
      if (_longeDemais) setState(() => _longeDemais = false);
      final v = visivel.area, c = _areaCarregada;
      if (_chaveCarregada != null &&
          c != null &&
          v.sul >= c.sul &&
          v.norte <= c.norte &&
          v.oeste >= c.oeste &&
          v.leste <= c.leste) {
        return;
      }
      final fLat = (v.norte - v.sul) * 0.25, fLon = (v.leste - v.oeste) * 0.25;
      final pedida = (sul: v.sul - fLat, oeste: v.oeste - fLon, norte: v.norte + fLat, leste: v.leste + fLon);
      area = pedida;
      chave = 'area:${[pedida.sul, pedida.oeste, pedida.norte, pedida.leste].map((x) => (x * 50).round()).join(':')}';
      consulta = () => Api.instancia.postosNaArea(pedida.sul, pedida.oeste, pedida.norte, pedida.leste);
    }
    // O fim de um movimento e a abertura da tela podem pedir a mesma área ao mesmo tempo
    if (_carregando && chave == _chavePedida) return;
    _chavePedida = chave;
    final pedido = ++_pedidos;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await consulta();
      // Uma área mais nova foi pedida enquanto esta carregava: a resposta antiga é descartada
      if (pedido != _pedidos) return;
      final loc = Localizacao.instancia;
      _postos = lista.map((p) => p.comDistancia(p.distanciaKm ?? loc.distanciaKm(p.lat, p.lon))).toList();
      _chaveCarregada = chave;
      _areaCarregada = area;
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

  /// Postos que aparecem no mapa: com posição e, no modo raio, dentro do círculo.
  List<PostoResumo> get _visiveis {
    if (_longeDemais) return const [];
    final raio = _porRaio ? Preferencias.raioKm.value : null;
    return _postos
        .where((p) => p.lat != null && p.lon != null && (raio == null || (p.distanciaKm != null && p.distanciaKm! <= raio)))
        .toList();
  }

  List<PostoResumo> _ordenadosPorPreco(List<PostoResumo> postos) {
    final produto = Preferencias.produto.value;
    final l = [...postos];
    l.sort((a, b) {
      final pa = a.preco(produto)?.preco, pb = b.preco(produto)?.preco;
      if (pa == null && pb == null) return (a.distanciaKm ?? 999).compareTo(b.distanciaKm ?? 999);
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pa.compareTo(pb);
    });
    return l;
  }

  /// Passa postos, posição e raio para as camadas do mapa nativo. As imagens de fundo dos pinos são
  /// registradas uma vez por aparência; o preço é texto do próprio mapa.
  Future<void> _desenhar(List<PostoResumo> postos) async {
    final estilo = _estiloMapa;
    if (estilo == null || !mounted) return;
    final desenho = ++_desenhos;
    final produto = Preferencias.produto.value;
    final cores = Tema.cores(context);
    final cs = Theme.of(context).colorScheme;
    final densidade = MediaQuery.devicePixelRatioOf(context);
    final aparencias = <String, AparenciaPino>{};
    final pontos = <Map<String, Object>>[];
    Map<String, Object>? pontoSelecionado;
    for (final p in postos) {
      final preco = p.preco(produto);
      final selecionado = p.id == _selecionado?.id;
      final a = AparenciaPino.de(preco, selecionado: selecionado, cores: cores, cs: cs);
      aparencias[a.id] = a;
      final feat = <String, Object>{
        'type': 'Feature',
        'geometry': {'type': 'Point', 'coordinates': [p.lon!, p.lat!]},
        'properties': {
          'id': p.id,
          'icone': a.id,
          'texto': textoPino(preco),
          'corTexto': a.corTextoHex,
          'ordem': preco == null ? 2 : 0,
        },
      };
      if (selecionado) {
        pontoSelecionado = feat;
      } else {
        pontos.add(feat);
      }
    }
    final pos = Localizacao.instancia.atual;
    final raio = Preferencias.raioKm.value;
    try {
      final imagens = _imagens;
      await Future.wait([
        for (final a in aparencias.values)
          imagens.putIfAbsent(a.id, () async => estilo.addImage(a.id, await a.png(densidade))),
      ]);
      if (desenho != _desenhos || estilo != _estiloMapa) return;
      await estilo.updateGeoJsonSource(
        id: CamadaPinos.fonte,
        data: jsonEncode({'type': 'FeatureCollection', 'features': pontos}),
      );
      await estilo.updateGeoJsonSource(
        id: CamadaPinos.idSelecionado,
        data: pontoSelecionado == null
            ? _geoVazio
            : jsonEncode({'type': 'FeatureCollection', 'features': [pontoSelecionado]}),
      );
      await estilo.updateGeoJsonSource(
        id: 'gasprice-usuario',
        data: pos == null
            ? _geoVazio
            : jsonEncode({
                'type': 'FeatureCollection',
                'features': [
                  {
                    'type': 'Feature',
                    'properties': <String, Object>{},
                    'geometry': {'type': 'Point', 'coordinates': [pos.longitude, pos.latitude]},
                  },
                ],
              }),
      );
      await estilo.updateGeoJsonSource(
        id: 'gasprice-raio',
        data: raio == null || pos == null ? _geoVazio : _circulo(pos.latitude, pos.longitude, raio),
      );
    } catch (e) {
      if (estilo == _estiloMapa && mounted) setState(() => _erro = 'Não foi possível desenhar os postos no mapa.\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final expandido = tamanhoDe(context) == Tamanho.expandido;
    final visiveis = _visiveis;
    final pos = Localizacao.instancia.atual;

    final retrato = Object.hash(
      Object.hashAll(visiveis.map((p) => p.id)),
      identityHashCode(_postos),
      _selecionado?.id,
      Preferencias.produto.value,
      pos?.latitude,
      pos?.longitude,
      Preferencias.raioKm.value,
      Theme.of(context).brightness,
      _estiloMapa,
    );
    if (!_semMapaNativo && _estiloMapa != null && retrato != _desenhado) {
      _desenhado = retrato;
      WidgetsBinding.instance.addPostFrameCallback((_) => _desenhar(visiveis));
    }

    final cs = Theme.of(context).colorScheme;

    final mapa = Stack(children: [
      if (_semMapaNativo)
        Positioned.fill(
          child: _MapaDeTeste(pinos: [
            for (final p in visiveis)
              _PinoPreco(
                posto: p,
                preco: p.preco(Preferencias.produto.value),
                selecionado: _selecionado?.id == p.id,
                aoTocar: () => _selecionar(p, mover: false),
              ),
          ]),
        )
      else
        MapLibreMap(
          options: _opcoes ??= _criarOpcoes(),
          onMapCreated: _aoCriar,
          onStyleLoaded: _aoCarregarEstilo,
          onEvent: _aoEvento,
        ),
      // Créditos
      Positioned(
        left: 8,
        right: 88,
        bottom: 8,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: _sobreOMapa(_Creditos(
            abertos: _creditosAbertos,
            aoAlternar: () => setState(() => _creditosAbertos = !_creditosAbertos),
          )),
        ),
      ),
      // Barra superior: busca + filtros
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _sobreOMapa(Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(28),
                color: cs.surfaceContainerHigh,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => context.go('/buscar'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      const Icon(Icons.search, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Buscar posto ou endereço',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
                      ),
                      if (_carregando) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ]),
                  ),
                ),
              ),
            )),
            _sobreOMapa(Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(children: [
                const SeletorProduto(),
                const SizedBox(width: 8),
                const SeletorRaio(),
              ]),
            )),
            if (!Config.configurado && !Config.demo)
              _sobreOMapa(const _Aviso('App sem conexão configurada com o Supabase. Veja o README.')),
            if (_longeDemais) _sobreOMapa(const _Aviso('Aproxime o mapa para ver os postos e preços.')),
            if (_erro != null) _sobreOMapa(_Aviso(_erro!)),
          ]),
        ),
      ),
      // FAB de localização
      Positioned(
        right: 16,
        bottom: _selecionado != null && !expandido ? 180 : 16,
        child: _sobreOMapa(FloatingActionButton.small(
          heroTag: 'centralizar',
          tooltip: 'Minha localização',
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 4,
          onPressed: _centralizar,
          child: const Icon(Icons.my_location),
        )),
      ),
      // Bottom sheet do posto selecionado
      if (_selecionado != null && !expandido)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _sobreOMapa(_FolhaPosto(
            posto: _selecionado!,
            produtoId: Preferencias.produto.value,
            aoFechar: () => setState(() => _selecionado = null),
          )),
        ),
    ]);

    return Scaffold(
      body: expandido
          ? Row(children: [
              Expanded(child: mapa),
              SizedBox(
                width: 380,
                child: _ListaLateral(
                  postos: _ordenadosPorPreco(visiveis),
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

/// Pino como widget, para os testes de widget, onde não há mapa nativo. Mesmo desenho do pino do mapa.
class _PinoPreco extends StatelessWidget {
  final PostoResumo posto;
  final PrecoAtual? preco;
  final bool selecionado;
  final VoidCallback aoTocar;
  const _PinoPreco({required this.posto, required this.preco, required this.selecionado, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final p = preco;
    final a = AparenciaPino.de(p, selecionado: selecionado, cores: Tema.cores(context), cs: Theme.of(context).colorScheme);
    final rotulo = p == null
        ? '${posto.nome}, sem preço'
        : '${posto.nome}, ${preco_(p.preco)}${p.fonte == FontePreco.estimativa ? ', estimativa' : ''}';
    // O pino do mapa tem tamanho fixo: a fonte cresce no máximo 15%
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Semantics(
        button: true,
        label: rotulo,
        child: GestureDetector(
          onTap: aoTocar,
          child: CustomPaint(
            painter: PintorPino(a),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                MedidasPino.margem + MedidasPino.folgaH,
                MedidasPino.margem + MedidasPino.folgaV,
                MedidasPino.margem + MedidasPino.folgaH,
                MedidasPino.folgaV + MedidasPino.ponta,
              ),
              child: ExcludeSemantics(
                child: Text(
                  textoPino(p),
                  style: TextStyle(color: a.corTexto, fontWeight: FontWeight.w800, fontSize: MedidasPino.fonte, height: 1.2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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

/// Usado só nos testes de widget, onde não há mapa nativo: os pinos ficam lado a lado sobre um fundo liso.
class _MapaDeTeste extends StatelessWidget {
  final List<Widget> pinos;
  const _MapaDeTeste({required this.pinos});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: pinos),
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

/// Folha inferior com resumo do posto. Aparece recolhida e pode ser arrastada para cima.
class _FolhaPosto extends StatelessWidget {
  final PostoResumo posto;
  final int produtoId;
  final VoidCallback aoFechar;
  const _FolhaPosto({required this.posto, required this.produtoId, required this.aoFechar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final p = posto.preco(produtoId);
    return Material(
      elevation: 8,
      color: cs.surfaceContainer,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Alça de arrasto
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
            // Nome + preço
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(posto.nome, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [posto.endereco, posto.bairro].where((e) => e != null && e.isNotEmpty).join(' · '),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (posto.distanciaKm != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(distancia(posto.distanciaKm), style: tt.bodySmall?.copyWith(color: cs.outline)),
                    ),
                ]),
              ),
              const SizedBox(width: 12),
              if (p != null)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(
                    p.fonte == FontePreco.estimativa ? '≈ ${preco(p.preco)}' : preco(p.preco),
                    style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    PontoFrescor(p.frescor()),
                    const SizedBox(width: 6),
                    SeloFonte(p),
                  ]),
                ])
              else
                Text('Sem preço', style: tt.bodyMedium?.copyWith(color: cs.outline)),
            ]),
            const SizedBox(height: 12),
            // Botões
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => context.push('/posto/${posto.id}/enviar'),
                  icon: const Icon(Icons.photo_camera_outlined, size: 20),
                  label: const Text('Atualizar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => context.push('/posto/${posto.id}'),
                  child: const Text('Ver detalhes'),
                ),
              ),
            ]),
          ]),
        ),
      ),
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
