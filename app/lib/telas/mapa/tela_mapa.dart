import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/localizacao.dart';
import '../../servicos/preferencias.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';
import '../../widgets/seletor_produto.dart';

/// Tela inicial: mapa do OpenStreetMap com os postos da área visível e o preço do combustível escolhido.
/// Não usa chave de API. Os blocos do mapa vêm de tile.openstreetmap.org, que exige a atribuição visível.
class TelaMapa extends StatefulWidget {
  const TelaMapa({super.key});
  @override
  State<TelaMapa> createState() => _TelaMapaState();
}

class _TelaMapaState extends State<TelaMapa> {
  static const _brasil = LatLng(-15.79, -47.88);
  static const _zoomMinimo = 11.0;
  static const _zoomLocal = 13.0;

  final _mapa = MapController();
  List<PostoResumo> _postos = [];
  PostoResumo? _selecionado;
  bool _carregando = false;
  bool _longeDemais = false;
  bool _mapaPronto = false;
  String? _erro;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    Preferencias.produto.addListener(_redesenhar);
    Localizacao.instancia.addListener(_redesenhar);
  }

  @override
  void dispose() {
    Preferencias.produto.removeListener(_redesenhar);
    Localizacao.instancia.removeListener(_redesenhar);
    _espera?.cancel();
    _mapa.dispose();
    super.dispose();
  }

  void _redesenhar() {
    if (mounted) setState(() {});
  }

  Future<void> _iniciar() async {
    _mapaPronto = true;
    final salvos = await Api.instancia.ultimaAreaSalva();
    if (salvos.isNotEmpty && mounted) setState(() => _postos = salvos);
    final pos = await Localizacao.instancia.obter(pedirPermissao: false);
    if (pos != null && mounted) {
      _mapa.move(LatLng(pos.latitude, pos.longitude), _zoomLocal);
    }
    _carregarArea();
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
    _mapa.move(LatLng(pos.latitude, pos.longitude), _zoomLocal);
  }

  void _aoMover(MapCamera camera, bool porGesto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 450), _carregarArea);
  }

  Future<void> _carregarArea() async {
    if (!_mapaPronto || !mounted || (!Config.configurado && !Config.demo)) return;
    final camera = _mapa.camera;
    if (camera.zoom < _zoomMinimo) {
      setState(() => _longeDemais = true);
      return;
    }
    setState(() {
      _longeDemais = false;
      _carregando = true;
      _erro = null;
    });
    try {
      final area = camera.visibleBounds;
      final lista = await Api.instancia.postosNaArea(area.south, area.west, area.north, area.east);
      final loc = Localizacao.instancia;
      _postos = lista.map((p) => p.comDistancia(loc.distanciaKm(p.lat, p.lon))).toList();
    } catch (e) {
      _erro = e.toString();
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _selecionar(PostoResumo p, {bool mover = true}) {
    setState(() => _selecionado = p);
    if (mover && p.lat != null) _mapa.move(LatLng(p.lat!, p.lon!), _mapa.camera.zoom);
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
    // Postos com preço por cima dos sem preço
    visiveis.sort((a, b) => (a.preco(produto) == null ? 0 : 1).compareTo(b.preco(produto) == null ? 0 : 1));
    final pos = Localizacao.instancia.atual;
    return [
      for (final p in visiveis)
        Marker(
          point: LatLng(p.lat!, p.lon!),
          width: 110,
          height: 44,
          alignment: Alignment.topCenter,
          child: _PinoPreco(
            posto: p,
            preco: p.preco(produto),
            selecionado: _selecionado?.id == p.id,
            aoTocar: () => _selecionar(p, mover: false),
          ),
        ),
      if (pos != null)
        Marker(
          point: LatLng(pos.latitude, pos.longitude),
          width: 22,
          height: 22,
          child: const _PontoUsuario(),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final expandido = tamanhoDe(context) == Tamanho.expandido;
    final cartaoAberto = _selecionado != null && !expandido;

    final mapa = Stack(children: [
      FlutterMap(
        mapController: _mapa,
        options: MapOptions(
          initialCenter: _brasil,
          initialZoom: 4.2,
          minZoom: 3,
          maxZoom: 18,
          onMapReady: _iniciar,
          onPositionChanged: _aoMover,
          onTap: (_, _) => setState(() => _selecionado = null),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'br.com.gasprice.gasprice',
            maxNativeZoom: 19,
          ),
          MarkerLayer(markers: _marcadores()),
          Padding(
            padding: EdgeInsets.only(bottom: cartaoAberto ? 212 : 0),
            child: RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution(
                  'Colaboradores do OpenStreetMap',
                  onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
                ),
              ],
            ),
          ),
        ],
      ),
      SafeArea(
        child: Column(children: [
          Padding(
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
          ),
          const SeletorProduto(sobreMapa: true),
          if (!Config.configurado && !Config.demo) const _Aviso('App sem conexão configurada com o Supabase. Veja o README.'),
          if (_longeDemais) const _Aviso('Aproxime o mapa para ver os postos e preços.'),
          if (_erro != null) _Aviso(_erro!),
        ]),
      ),
      Positioned(
        right: 16,
        bottom: cartaoAberto ? 228 : 16,
        child: FloatingActionButton(
          heroTag: 'centralizar',
          tooltip: 'Minha localização',
          onPressed: _centralizar,
          child: const Icon(Icons.my_location),
        ),
      ),
      if (cartaoAberto)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _CartaoSelecionado(posto: _selecionado!, produtoId: Preferencias.produto.value),
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

/// Pino com o preço, colorido pela idade do dado.
class _PinoPreco extends StatelessWidget {
  final PostoResumo posto;
  final PrecoAtual? preco;
  final bool selecionado;
  final VoidCallback aoTocar;
  const _PinoPreco({required this.posto, required this.preco, required this.selecionado, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final p = preco;
    final cor = p == null
        ? const Color(0xFF6B7280)
        : (p.fonte == FontePreco.estimativa ? Tema.estimativa : corFrescor(p.frescor()));
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: selecionado ? Colors.black : Colors.white, width: selecionado ? 2.5 : 1.5),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (posto.precisao.aproximada) ...[
                const Icon(Icons.location_searching, size: 13, color: Colors.white),
                const SizedBox(width: 3),
              ],
              Text(texto,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, height: 1.1)),
            ]),
          ),
          CustomPaint(size: const Size(12, 7), painter: _Ponta(cor)),
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
  Widget build(BuildContext context) => Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CartaoPosto(posto: posto, produtoId: produtoId, aoTocar: () => context.push('/posto/${posto.id}')),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/posto/${posto.id}/enviar'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Atualizar preço'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => context.push('/posto/${posto.id}'),
                  child: const Text('Ver posto'),
                ),
              ),
            ]),
          ),
        ]),
      );
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
