import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';
import '../../widgets/grafico_historico.dart';

/// Histórico de preço de um combustível, com período ajustável e origem de cada ponto.
class TelaHistorico extends StatefulWidget {
  final int postoId;
  final int produtoId;
  const TelaHistorico({super.key, required this.postoId, required this.produtoId});
  @override
  State<TelaHistorico> createState() => _TelaHistoricoState();
}

class _TelaHistoricoState extends State<TelaHistorico> {
  late int _produto = widget.produtoId;
  int _dias = 180;
  late Future<List<PontoHistorico>> _dados = _carregar();

  static const _periodos = [(30, '30 dias'), (90, '3 meses'), (180, '6 meses'), (365, '1 ano'), (730, '2 anos')];

  Future<List<PontoHistorico>> _carregar() => Api.instancia.historico(widget.postoId, _produto, _dias);
  void _mudar(void Function() f) => setState(() {
        f();
        _dados = _carregar();
      });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    // No tablet em paisagem, gráfico à esquerda e registros à direita
    final expandido = tamanhoDe(context) == Tamanho.expandido;
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de preços')),
      body: LarguraMaxima(
        maxima: expandido ? larguraListas : 900,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final p in Produto.todos)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(p.nome), selected: _produto == p.id, onSelected: (_) => _mudar(() => _produto = p.id)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          // Rola de lado quando os 5 períodos não cabem (tela estreita ou fonte ampliada)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: [for (final (d, t) in _periodos) ButtonSegment(value: d, label: Text(t, maxLines: 1, softWrap: false))],
              selected: {_dias},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _mudar(() => _dias = s.first),
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<PontoHistorico>>(
            future: _dados,
            builder: (context, snap) {
              if (snap.hasError) return EstadoErro(snap.error!, () => _mudar(() {}));
              if (!snap.hasData) return const SizedBox(height: 280, child: Center(child: CircularProgressIndicator()));
              final pontos = snap.data!;
              final anp = pontos.where((p) => p.anp).toList();
              final com = pontos.where((p) => !p.anp).toList();
              final grafico = Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    GraficoHistorico(pontos: pontos),
                    const Padding(padding: EdgeInsets.fromLTRB(8, 12, 0, 4), child: LegendaHistorico()),
                  ]),
                ),
              );
              final registros = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (pontos.isNotEmpty) ...[
                  Text('Todos os registros', style: tt.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(children: [
                      for (final p in pontos.reversed.take(60))
                        ListTile(
                          dense: true,
                          leading: Icon(
                            p.anp ? Icons.account_balance_outlined : Icons.photo_camera_outlined,
                            color: p.anp ? Tema.cores(context).anp : Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(data(p.dia)),
                          subtitle: Text(p.anp ? 'Pesquisa ANP' : 'Comunidade'),
                          trailing: Text(preco(p.preco), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text('${anp.length} registros da ANP e ${com.length} da comunidade no período.', style: tt.bodySmall),
                ],
              ]);
              if (expandido) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: grafico),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: registros),
                ]);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [grafico, const SizedBox(height: 16), registros],
              );
            },
          ),
        ]),
      ),
    );
  }
}
