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
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: lista.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final r = lista[i];
                  final medalha = switch (r.posicao) {
                    1 => const Color(0xFFD4A017),
                    2 => const Color(0xFF9EA7AD),
                    3 => const Color(0xFFB0703A),
                    _ => null,
                  };
                  return Card(
                    color: r.souEu ? cs.secondaryContainer : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: medalha ?? cs.surfaceContainerHighest,
                        foregroundColor: medalha == null ? cs.onSurface : Colors.white,
                        child: Text('${r.posicao}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      title: Text(r.souEu ? '${r.autor} (você)' : r.autor),
                      trailing: Text('${r.pontos} pts', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ),
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
