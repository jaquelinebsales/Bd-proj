import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';

/// Ranking da comunidade por pontos. Os nomes aparecem abreviados.
class TelaRanking extends StatefulWidget {
  const TelaRanking({super.key});
  @override
  State<TelaRanking> createState() => _TelaRankingState();
}

class _TelaRankingState extends State<TelaRanking> {
  late Future<List<ItemRanking>> _ranking = Api.instancia.ranking();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ranking da comunidade')),
      body: LarguraMaxima(
        maxima: larguraListas,
        child: FutureBuilder<List<ItemRanking>>(
          future: _ranking,
          builder: (context, snap) {
            if (snap.hasError) return EstadoErro(snap.error!, () => setState(() => _ranking = Api.instancia.ranking()));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final lista = snap.data!;
            if (lista.isEmpty) {
              return const EstadoVazio(
                icone: Icons.emoji_events_outlined,
                titulo: 'O ranking ainda está vazio',
                texto: 'Os primeiros envios confirmados da comunidade aparecem aqui.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                setState(() => _ranking = Api.instancia.ranking());
                await _ranking;
              },
              // No tablet em paisagem, três por linha: a primeira linha vira o pódio
              child: GradeDeCartoes(
                colunas: colunasDeCartoes(context),
                padding: const EdgeInsets.all(16),
                quantidade: lista.length,
                cartao: (context, i) {
                  final r = lista[i];
                  final medalha = switch (r.posicao) {
                    1 => const Color(0xFFD4A017),
                    2 => const Color(0xFF9EA7AD),
                    3 => const Color(0xFFB0703A),
                    _ => null,
                  };
                  return CartaoLinha(
                    cor: r.souEu ? cs.secondaryContainer : null,
                    inicio: CircleAvatar(
                      backgroundColor: medalha ?? cs.surfaceContainerHighest,
                      foregroundColor: medalha == null ? cs.onSurface : Colors.white,
                      child: Text('${r.posicao}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    titulo: r.souEu ? '${r.autor} (você)' : r.autor,
                    fim: Text('${r.pontos} pts', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
