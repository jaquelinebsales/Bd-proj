import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
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
import '../../servicos/monitor_demo.dart';
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
  static const _centroDemo = Geographic(lon: -38.535, lat: -3.785);
  static const _zoomBrasil = 3.2;
  static const _zoomMinimo = 10.0;
  static const _zoomLocal = 12.0;
  static const _estiloClaro = 'https://tiles.openfreemap.org/styles/positron';
  static const _estiloEscuro = 'https://tiles.openfreemap.org/styles/dark';

  /// Nos testes de widget não existe mapa nativo: a tela desenha os pinos lado a lado sobre um fundo liso.
  static final _semMapaNativo = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Estilos com os rótulos em português, já baixados (por URL do estilo).
  static final _estilosPt = <String, String>{};

  MapController? _mapa;
  MapOptions? _opcoes;
  String? _estilo;
  String? _fonteAtual;
  bool _estiloPronto = false;
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
  // Imagens dos pinos já postas no estilo atual e as que podem ter sobrado do anterior
  Set<String> _imagensAdicionadas = {};
  Set<String> _imagensAntigas = {};
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
      // O mapa espera o estilo em português por até 3 s; sem ele, abre com o original e troca quando chegar
      Future.any<void>([
        Future.wait([_traduzirEstilo(_estiloClaro), _traduzirEstilo(_estiloEscuro)]).then((_) {}),
        Future<void>.delayed(const Duration(seconds: 3)),
      ]).whenComplete(() {
        if (mounted) setState(() => _estiloPronto = true);
      });
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
    final mudou = _estilo != null && estilo != _estilo;
    _estilo = estilo;
    if (mudou) _aplicarEstilo();
  }

  /// O estilo do OpenFreeMap prefere o nome em inglês dos lugares ("Centre" no lugar de "Centro").
  /// Os rótulos passam a usar o nome em português, com o nome local de reserva.
  static Future<String?> _traduzirEstilo(String url) async {
    final pronto = _estilosPt[url];
    if (pronto != null) return pronto;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final estilo = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      for (final camada in (estilo['layers'] as List).whereType<Map<String, dynamic>>()) {
        // A textura de mata não existe no sprite do OpenFreeMap: sem ela, a área usa só a cor de preenchimento
        final pintura = camada['paint'];
        if (pintura is Map && pintura['fill-pattern'] == 'wood-pattern') pintura.remove('fill-pattern');
        final layout = camada['layout'];
        if (layout is Map && jsonEncode(layout['text-field']).contains('name_en')) {
          layout['text-field'] = [
            'coalesce',
            ['get', 'name:pt'],
            ['get', 'name'],
          ];
        }
      }
      return _estilosPt[url] = jsonEncode(estilo);
    } catch (_) {
      return null;
    }
  }

  String _fonteEstilo(String url) => _estilosPt[url] ?? url;

  /// Usa o estilo em português assim que estiver baixado; até lá, o original pela URL.
  void _aplicarEstilo() {
    final url = _estilo, mapa = _mapa;
    if (url == null || mapa == null) return;
    final fonte = _fonteEstilo(url);
    if (fonte != _fonteAtual) {
      _fonteAtual = fonte;
      mapa.setStyle(fonte);
    }
    if (!_estilosPt.containsKey(url)) {
      _traduzirEstilo(url).then((_) {
        if (mounted && _estilo == url) _aplicarEstilo();
      });
    }
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
    _desselecionar();
    if (_porRaio) unawaited(_enquadrarRaio());
    _carregarArea();
  }

  MapOptions _criarOpcoes() {
    final pos = Localizacao.instancia.atual;
    _fonteAtual = _fonteEstilo(_estilo ?? _estiloClaro);
    return MapOptions(
      initStyle: _fonteAtual!,
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
    // O tema pode ter mudado entre a criação das opções e a do mapa, ou o estilo em português pode ter chegado
    _aplicarEstilo();
    _iniciar();
  }

  /// Cada estilo novo (inclusive na troca de tema) chega sem as camadas do app: elas são criadas de novo.
  Future<void> _aoCarregarEstilo(StyleController estilo) async {
    _estiloMapa = estilo;
    _imagens = {};
    _desenhado = null;
    final marca = _hex(Theme.of(context).colorScheme.primary);
    const fontes = ['gasprice-raio', 'gasprice-usuario', CamadaPinos.fonte, CamadaPinos.idSelecionado];
    const camadas = ['gasprice-raio-area', 'gasprice-raio-borda', 'gasprice-usuario-halo', 'gasprice-usuario',
        CamadaPinos.id, CamadaPinos.idSelecionado];
    try {
      // Na web, trocar o estilo pode manter as camadas do app do estilo anterior: só essas saem antes de voltar.
      // Remover às cegas faz o MapLibre registrar um erro no console para cada camada que não existe.
      // ignore: invalid_use_of_visible_for_testing_member
      final existentes = estilo.getLayerIds().toSet();
      final herdou = existentes.contains(CamadaPinos.id);
      _imagensAntigas = herdou ? {..._imagensAdicionadas} : {};
      _imagensAdicionadas = {};
      for (final c in camadas.reversed.where(existentes.contains)) {
        await estilo.removeLayer(c);
      }
      if (herdou) {
        for (final f in fontes) {
          try {
            await estilo.removeSource(f);
          } catch (_) {}
        }
      }
      for (final id in fontes) {
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
    } else {
      _desselecionar();
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
        // Também sem posição: na web os pinos só aparecem depois do primeiro movimento da câmera.
        // Na demonstração o mapa abre um pouco ao sul, para Fortaleza não aparecer com metade da tela no mar.
        await mapa.moveCamera(
          center: Config.demo
              ? _centroDemo
              : pos == null
                  ? mapa.getCamera().center
                  : Geographic(lon: pos.longitude, lat: pos.latitude),
          zoom: Config.demo ? 11.2 : (pos == null ? null : _zoomLocal),
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

  // Na demonstração, o resumo do posto aberto é explicado ao lado; ao fechar, volta a explicação do mapa
  void _desselecionar() {
    if (_selecionado == null) return;
    setState(() => _selecionado = null);
    MonitorDemo.fechou();
  }

  void _selecionar(PostoResumo p, {bool mover = true}) {
    if (_selecionado?.id != p.id) MonitorDemo.toque('Posto selecionado');
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
    final produto = Preferencias.primario;
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
    final produtos = Preferencias.produto.value;
    final cores = Tema.cores(context);
    final cs = Theme.of(context).colorScheme;
    final densidade = MediaQuery.devicePixelRatioOf(context);
    final aparencias = <String, AparenciaPino>{};
    final pontos = <Map<String, Object>>[];
    Map<String, Object>? pontoSelecionado;
    for (final p in postos) {
      final preco = p.melhorPreco(produtos);
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
          imagens.putIfAbsent(a.id, () async {
            final png = await a.png(densidade);
            // A imagem só pode ter sobrado se o estilo anterior foi mantido (troca de tema na web)
            if (_imagensAntigas.remove(a.id)) {
              try {
                await estilo.removeImage(a.id);
              } catch (_) {}
            }
            await estilo.addImage(a.id, png);
            _imagensAdicionadas.add(a.id);
          }),
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
                preco: p.melhorPreco(Preferencias.produto.value),
                selecionado: _selecionado?.id == p.id,
                aoTocar: () => _selecionar(p, mover: false),
              ),
          ]),
        )
      else if (!_estiloPronto)
        Positioned.fill(child: ColoredBox(color: cs.surfaceContainerHighest))
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
        bottom: _selecionado != null && !expandido ? 196 : 16,
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
        Positioned.fill(
          child: _sobreOMapa(_FolhaPosto(
            posto: _selecionado!,
            produtoId: Preferencias.primario,
            aoFechar: _desselecionar,
          )),
        ),
    ]);

    // A mesma estrutura nos dois tamanhos: ao girar o tablet (ou redimensionar a janela) o mapa continua o mesmo
    // widget. Se ele mudasse de lugar na árvore, o Flutter criaria outro mapa e o app desenharia no antigo.
    return Scaffold(
      body: Row(children: [
        Expanded(child: mapa),
        if (expandido)
          SizedBox(
            width: 380,
            child: _ListaLateral(
              postos: _ordenadosPorPreco(visiveis),
              selecionado: _selecionado,
              aoSelecionar: _selecionar,
              longeDemais: _longeDemais,
            ),
          ),
      ]),
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

/// Folha inferior com resumo do posto. Recolhida mostra o cartão; ao arrastar para cima expande
/// para mostrar todos os preços e informações do posto.
class _FolhaPosto extends StatefulWidget {
  final PostoResumo posto;
  final int produtoId;
  final VoidCallback aoFechar;
  const _FolhaPosto({required this.posto, required this.produtoId, required this.aoFechar});

  @override
  State<_FolhaPosto> createState() => _FolhaPostoState();
}

class _FolhaPostoState extends State<_FolhaPosto> {
  final _ctrl = DraggableScrollableController();
  bool _expandido = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_aoMudar);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_aoMudar);
    _ctrl.dispose();
    super.dispose();
  }

  void _aoMudar() {
    if (!_ctrl.isAttached) return;
    final exp = _ctrl.size > 0.5;
    if (exp != _expandido) setState(() => _expandido = exp);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _ctrl,
      initialChildSize: 0.28,
      minChildSize: 0.28,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.28, 0.92],
      builder: (context, scrollCtrl) => _conteudo(context, scrollCtrl),
    );
  }

  Widget _conteudo(BuildContext context, ScrollController scrollCtrl) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final posto = widget.posto;
    final p = posto.preco(widget.produtoId);
    final precosDisponiveis = Produto.todos.where((pr) => posto.preco(pr.id) != null).toList();

    return Material(
      elevation: 8,
      color: cs.surfaceContainer,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          controller: scrollCtrl,
          physics: const ClampingScrollPhysics(),
          slivers: [
            // Cabeçalho fixo: alça, nome, preço, botões
            SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Alça + botão fechar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                  child: Row(children: [
                    const Spacer(),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: 'Fechar',
                          onPressed: widget.aoFechar,
                        ),
                      ),
                    ),
                  ]),
                ),
                // Nome + preço
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(posto.nome,
                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          [posto.endereco, posto.bairro]
                              .where((e) => e != null && e.isNotEmpty)
                              .join(' · '),
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (posto.distanciaKm != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(distancia(posto.distanciaKm),
                                style: tt.bodySmall?.copyWith(color: cs.outline)),
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
                ),
                // Botões
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(children: [
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
                ),
              ]),
            ),
            // Conteúdo expandido: todos os preços e informações
            if (_expandido) ...[
              SliverToBoxAdapter(child: Divider(height: 1, color: cs.outlineVariant)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Text('Preços',
                      style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                ),
              ),
              if (precosDisponiveis.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text('Nenhum preço cadastrado.',
                        style: tt.bodyMedium?.copyWith(color: cs.outline)),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final pr = precosDisponiveis[i];
                      final pc = posto.preco(pr.id)!;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        title: Text(pr.nome, style: tt.bodyMedium),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          PontoFrescor(pc.frescor()),
                          const SizedBox(width: 8),
                          Text(
                            pc.fonte == FontePreco.estimativa
                                ? '≈ ${preco(pc.preco)}'
                                : preco(pc.preco),
                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ]),
                      );
                    },
                    childCount: precosDisponiveis.length,
                  ),
                ),
              if (posto.notaMedia != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: Row(children: [
                      Icon(Icons.star_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(
                        '${posto.notaMedia!.toStringAsFixed(1).replaceAll('.', ',')}  (${posto.totalAvaliacoes} avaliações)',
                        style: tt.bodySmall,
                      ),
                    ]),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
              ),
            ],
          ],
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
    final produto = Preferencias.primario;
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
