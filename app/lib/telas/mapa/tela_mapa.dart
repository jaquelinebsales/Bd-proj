import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../config.dart';
import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/localizacao.dart';
import '../../servicos/preferencias.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';
import '../../widgets/marcador.dart';
import '../../widgets/seletor_produto.dart';

/// Tela inicial: mapa com os postos da área visível e o preço do combustível escolhido.
class TelaMapa extends StatefulWidget {
  const TelaMapa({super.key});
  @override
  State<TelaMapa> createState() => _TelaMapaState();
}

class _TelaMapaState extends State<TelaMapa> {
  static const _brasil = CameraPosition(target: LatLng(-15.79, -47.88), zoom: 4.2);
  static const _zoomMinimo = 11.0;

  GoogleMapController? _mapa;
  final _marcadores = FabricaMarcadores();
  Set<Marker> _pinos = {};
  List<PostoResumo> _postos = [];
  PostoResumo? _selecionado;
  bool _carregando = false;
  bool _longeDemais = false;
  String? _erro;
  Timer? _espera;
  double _zoom = _brasil.zoom;

  @override
  void initState() {
    super.initState();
    Preferencias.produto.addListener(_redesenhar);
  }

  @override
  void dispose() {
    Preferencias.produto.removeListener(_redesenhar);
    _espera?.cancel();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final salvos = await Api.instancia.ultimaAreaSalva();
    if (salvos.isNotEmpty && mounted) {
      _postos = salvos;
      await _redesenhar();
    }
    final pos = await Localizacao.instancia.obter(pedirPermissao: false);
    if (pos != null) {
      await _mapa?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14));
    }
  }

  Future<void> _centralizar() async {
    final pos = await Localizacao.instancia.obter();
    if (pos == null) {
      if (!mounted) return;
      final estado = Localizacao.instancia.estado;
      mostrarMensagem(
        context,
        estado == EstadoLocalizacao.desligada
            ? 'Ative a localização do aparelho para ver os postos perto de você.'
            : 'Permita o acesso à localização nas configurações do app.',
      );
      return;
    }
    await _mapa?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14));
  }

  void _aoParar() {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 450), _carregarArea);
  }

  Future<void> _carregarArea() async {
    final mapa = _mapa;
    if (mapa == null || (!Config.configurado && !Config.demo)) return;
    if (_zoom < _zoomMinimo) {
      setState(() {
        _longeDemais = true;
        _pinos = {};
      });
      return;
    }
    setState(() {
      _longeDemais = false;
      _carregando = true;
      _erro = null;
    });
    try {
      final area = await mapa.getVisibleRegion();
      final lista = await Api.instancia.postosNaArea(
        area.southwest.latitude, area.southwest.longitude, area.northeast.latitude, area.northeast.longitude);
      final loc = Localizacao.instancia;
      _postos = lista.map((p) => p.comDistancia(loc.distanciaKm(p.lat, p.lon))).toList();
      await _redesenhar();
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _redesenhar() async {
    final produto = Preferencias.produto.value;
    final pinos = <Marker>{};
    final cs = Theme.of(context).colorScheme;
    for (final p in _postos) {
      if (p.lat == null || p.lon == null) continue;
      final pr = p.preco(produto);
      final cor = pr == null ? const Color(0xFF6B7280) : (pr.fonte == FontePreco.estimativa ? Tema.estimativa : corFrescor(pr.frescor()));
      final texto = pr == null ? '–' : (pr.fonte == FontePreco.estimativa ? '≈${preco(pr.preco)}' : preco(pr.preco)).replaceAll('R\$ ', '');
      final icone = await _marcadores.pilula(texto, cor, _selecionado?.id == p.id ? cs.onSurface : Colors.white);
      pinos.add(Marker(
        markerId: MarkerId('${p.id}'),
        position: LatLng(p.lat!, p.lon!),
        icon: icone,
        anchor: const Offset(0.5, 1),
        zIndexInt: pr == null ? 0 : 1,
        onTap: () => _selecionar(p, mover: false),
      ));
    }
    if (mounted) setState(() => _pinos = pinos);
  }

  void _selecionar(PostoResumo p, {bool mover = true}) {
    setState(() => _selecionado = p);
    _redesenhar();
    if (mover && p.lat != null) _mapa?.animateCamera(CameraUpdate.newLatLng(LatLng(p.lat!, p.lon!)));
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

  @override
  Widget build(BuildContext context) {
    final expandido = tamanhoDe(context) == Tamanho.expandido;
    final mapa = Stack(children: [
      GoogleMap(
        initialCameraPosition: _brasil,
        onMapCreated: (c) {
          _mapa = c;
          _iniciar();
        },
        onCameraMove: (pos) => _zoom = pos.zoom,
        onCameraIdle: _aoParar,
        onTap: (_) => setState(() => _selecionado = null),
        markers: _pinos,
        myLocationEnabled: Localizacao.instancia.estado == EstadoLocalizacao.permitida,
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        zoomControlsEnabled: false,
        padding: EdgeInsets.only(top: 120, bottom: _selecionado != null && !expandido ? 200 : 0),
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
        bottom: _selecionado != null && !expandido ? 216 : 16,
        child: FloatingActionButton(
          heroTag: 'centralizar',
          tooltip: 'Minha localização',
          onPressed: _centralizar,
          child: const Icon(Icons.my_location),
        ),
      ),
      if (_selecionado != null && !expandido)
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
