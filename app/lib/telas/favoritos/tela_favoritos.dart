import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/favoritos.dart';
import '../../servicos/localizacao.dart';
import '../../servicos/preferencias.dart';
import '../../servicos/sessao.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';
import '../../widgets/seletor_produto.dart';

/// Postos favoritos com preço atual e data da última atualização.
/// Sem login, os favoritos ficam só neste aparelho.
class TelaFavoritos extends StatefulWidget {
  const TelaFavoritos({super.key});
  @override
  State<TelaFavoritos> createState() => _TelaFavoritosState();
}

class _TelaFavoritosState extends State<TelaFavoritos> {
  late Future<List<PostoResumo>> _lista = _carregar();
  Set<int> _idsCarregados = {};

  @override
  void initState() {
    super.initState();
    Favoritos.instancia.addListener(_aoMudarFavoritos);
    Preferencias.produto.addListener(_redesenhar);
  }

  @override
  void dispose() {
    Favoritos.instancia.removeListener(_aoMudarFavoritos);
    Preferencias.produto.removeListener(_redesenhar);
    super.dispose();
  }

  void _redesenhar() => setState(() {});

  void _aoMudarFavoritos() {
    if (Favoritos.instancia.ids.difference(_idsCarregados).isNotEmpty ||
        _idsCarregados.difference(Favoritos.instancia.ids).isNotEmpty) {
      setState(() => _lista = _carregar());
    }
  }

  Future<List<PostoResumo>> _carregar() async {
    _idsCarregados = {...Favoritos.instancia.ids};
    final lista = Sessao.instancia.logado
        ? await Api.instancia.meusFavoritos()
        : await Api.instancia.postosPorIds(_idsCarregados.toList());
    final loc = Localizacao.instancia;
    return lista.map((p) => p.comDistancia(loc.distanciaKm(p.lat, p.lon))).toList();
  }

  Future<void> _alternarAviso(PostoResumo p) async {
    try {
      await Api.instancia.notificarFavorito(p.id, !p.notificar);
      setState(() => _lista = _carregar());
      if (mounted) {
        mostrarMensagem(context, p.notificar ? 'Avisos desligados para este posto.' : 'Você será avisado quando o preço mudar.');
      }
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logado = Sessao.instancia.logado;
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: LarguraMaxima(
        maxima: 900,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: const Row(children: [SeletorProduto()]),
          ),
          if (!logado)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Favoritos salvos só neste aparelho'),
                  trailing: TextButton(onPressed: () => context.push('/entrar'), child: const Text('Entrar')),
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<PostoResumo>>(
              future: _lista,
              builder: (context, snap) {
                if (snap.hasError) return EstadoErro(snap.error!, () => setState(() => _lista = _carregar()));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final postos = snap.data!;
                if (postos.isEmpty) {
                  return EstadoVazio(
                    icone: Icons.favorite_outline,
                    titulo: 'Nenhum favorito ainda',
                    texto: 'Toque no coração na página de um posto para acompanhar o preço dele aqui.',
                    acao: OutlinedButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Ir para o mapa'),
                    ),
                  );
                }
                final colunas = tamanhoDe(context) == Tamanho.compacto ? 1 : 2;
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _lista = _carregar());
                    await _lista;
                  },
                  child: GradeDeCartoes(
                    colunas: colunas,
                    alturaBase: logado ? 172 : 142,
                    padding: const EdgeInsets.all(12),
                    quantidade: postos.length,
                    cartao: (context, i) {
                      final p = postos[i];
                      return CartaoPosto(
                        posto: p,
                        produtoId: Preferencias.produto.value,
                        aoTocar: () => context.push('/posto/${p.id}'),
                        acao: logado
                            ? IconButton(
                                tooltip: p.notificar ? 'Desligar avisos de preço' : 'Ligar avisos de preço',
                                onPressed: () => _alternarAviso(p),
                                icon: Icon(p.notificar ? Icons.notifications_active : Icons.notifications_off_outlined),
                              )
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
