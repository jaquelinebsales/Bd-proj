import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/favoritos.dart';
import '../../servicos/filtros.dart';
import '../../servicos/localizacao.dart';
import '../../servicos/preferencias.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';
import '../../widgets/seletor_produto.dart';
import 'filtros_sheet.dart';

/// Busca por nome, endereço, bairro, cidade ou região, com filtros e ordenação no aparelho.
class TelaBusca extends StatefulWidget {
  const TelaBusca({super.key});
  @override
  State<TelaBusca> createState() => _TelaBuscaState();
}

class _TelaBuscaState extends State<TelaBusca> {
  final _texto = TextEditingController();
  Timer? _espera;
  List<PostoResumo> _resultados = [];
  Filtros _filtros = Filtros(produtoId: Preferencias.produto.value);
  bool _carregando = false;
  Object? _erro;
  bool _semLocalizacao = false;

  @override
  void initState() {
    super.initState();
    Preferencias.produto.addListener(_aoMudarProduto);
    Favoritos.instancia.addListener(_atualizarTela);
    _carregar();
  }

  @override
  void dispose() {
    Preferencias.produto.removeListener(_aoMudarProduto);
    Favoritos.instancia.removeListener(_atualizarTela);
    _espera?.cancel();
    _texto.dispose();
    super.dispose();
  }

  void _atualizarTela() => setState(() {});
  void _aoMudarProduto() => setState(() => _filtros = _filtros.copiar(produtoId: Preferencias.produto.value));

  void _aoDigitar(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), _carregar);
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final loc = Localizacao.instancia;
      final pos = loc.atual ?? await loc.obter(pedirPermissao: false);
      final termo = _texto.text.trim();
      List<PostoResumo> lista;
      if (termo.length >= 2) {
        lista = await Api.instancia.buscar(termo, lat: pos?.latitude, lon: pos?.longitude);
        _semLocalizacao = false;
      } else if (pos != null) {
        lista = await Api.instancia.postosProximos(pos.latitude, pos.longitude, raioKm: 20);
        _semLocalizacao = false;
      } else {
        lista = [];
        _semLocalizacao = true;
      }
      _resultados = lista.map((p) => p.comDistancia(p.distanciaKm ?? loc.distanciaKm(p.lat, p.lon))).toList();
    } catch (e) {
      _erro = e;
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirFiltros() async {
    final novo = await mostrarFiltros(context, _filtros);
    if (novo != null) {
      setState(() => _filtros = novo);
      if (novo.produtoId != Preferencias.produto.value) Preferencias.produto.value = novo.produtoId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visiveis = aplicarFiltros(_resultados, _filtros, favoritos: Favoritos.instancia.ids);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LarguraMaxima(
          maxima: 900,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: SearchBar(
                controller: _texto,
                hintText: 'Nome, endereço, bairro, cidade ou UF',
                leading: const Icon(Icons.search),
                onChanged: _aoDigitar,
                onSubmitted: (_) => _carregar(),
                trailing: [
                  if (_texto.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _texto.clear();
                        _carregar();
                      },
                    ),
                ],
              ),
            ),
            const SeletorProduto(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _carregando
                        ? 'Buscando…'
                        : _texto.text.trim().length >= 2
                            ? '${visiveis.length} postos encontrados'
                            : '${visiveis.length} postos em até 20 km',
                    style: tt.bodyMedium,
                  ),
                ),
                PopupMenuButton<Ordenacao>(
                  tooltip: 'Ordenar',
                  initialValue: _filtros.ordenacao,
                  onSelected: (o) => setState(() => _filtros = _filtros.copiar(ordenacao: o)),
                  itemBuilder: (_) => [for (final o in Ordenacao.values) PopupMenuItem(value: o, child: Text(o.texto))],
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.sort, size: 20),
                      const SizedBox(width: 4),
                      Text(_filtros.ordenacao.texto),
                    ]),
                  ),
                ),
                IconButton(
                  tooltip: 'Filtros',
                  onPressed: _abrirFiltros,
                  icon: Badge(
                    isLabelVisible: _filtros.ativos > 0,
                    label: Text('${_filtros.ativos}'),
                    child: const Icon(Icons.tune),
                  ),
                ),
              ]),
            ),
            if (_carregando) const LinearProgressIndicator(),
            Expanded(child: _corpo(visiveis)),
          ]),
        ),
      ),
    );
  }

  Widget _corpo(List<PostoResumo> visiveis) {
    if (_erro != null) return EstadoErro(_erro!, _carregar);
    if (_semLocalizacao && _texto.text.trim().length < 2) {
      return EstadoVazio(
        icone: Icons.location_searching,
        titulo: 'Busque uma cidade ou endereço',
        texto: 'Digite onde quer abastecer, ou permita a localização para ver os postos perto de você.',
        acao: OutlinedButton.icon(
          onPressed: () async {
            await Localizacao.instancia.obter();
            _carregar();
          },
          icon: const Icon(Icons.my_location),
          label: const Text('Usar minha localização'),
        ),
      );
    }
    if (!_carregando && visiveis.isEmpty) {
      return EstadoVazio(
        icone: Icons.search_off,
        titulo: 'Nenhum posto encontrado',
        texto: _filtros.ativos > 0 ? 'Tente remover alguns filtros.' : 'Confira a grafia ou busque pela cidade.',
        acao: _filtros.ativos > 0
            ? TextButton(
                onPressed: () => setState(() => _filtros = Filtros(produtoId: _filtros.produtoId, ordenacao: _filtros.ordenacao)),
                child: const Text('Limpar filtros'),
              )
            : null,
      );
    }
    final colunas = tamanhoDe(context) == Tamanho.compacto ? 1 : 2;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: GradeDeCartoes(
        colunas: colunas,
        alturaBase: 142,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        quantidade: visiveis.length,
        cartao: (context, i) => CartaoPosto(
          posto: visiveis[i],
          produtoId: _filtros.produtoId,
          aoTocar: () => context.push('/posto/${visiveis[i].id}'),
        ),
      ),
    );
  }
}
