import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/comuns.dart';

/// Folha "Contribuições": quem enviou o preço, variações reportadas e o dado oficial da ANP.
Future<void> mostrarContribuicoes(BuildContext context, PostoDetalhe posto, int produtoId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Contribuicoes(posto: posto, produtoId: produtoId),
    );

class _Contribuicoes extends StatefulWidget {
  final PostoDetalhe posto;
  final int produtoId;
  const _Contribuicoes({required this.posto, required this.produtoId});
  @override
  State<_Contribuicoes> createState() => _ContribuicoesState();
}

class _ContribuicoesState extends State<_Contribuicoes> {
  late Future<(List<Contribuicao>, PontoHistorico?)> _dados = _carregar();

  Future<(List<Contribuicao>, PontoHistorico?)> _carregar() async {
    final api = Api.instancia;
    final r = await Future.wait([
      api.contribuicoes(widget.posto.resumo.id, widget.produtoId),
      api.historico(widget.posto.resumo.id, widget.produtoId, 120),
    ]);
    final hist = (r[1] as List<PontoHistorico>).where((p) => p.anp).toList();
    return (r[0] as List<Contribuicao>, hist.isEmpty ? null : hist.last);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final atual = widget.posto.resumo.preco(widget.produtoId);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, rolagem) => FutureBuilder(
        future: _dados,
        builder: (context, snap) {
          if (snap.hasError) {
            return EstadoErro(snap.error!, () => setState(() => _dados = _carregar()));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (contrib, anp) = snap.data!;
          final referencia = atual?.preco;
          final confirmadas = contrib
              .where((c) => referencia != null && (c.preco - referencia).abs() <= 0.02 && c.status != 'contestado')
              .toList();
          final outras = contrib.where((c) => !confirmadas.contains(c)).toList();

          final confianca = atual == null
              ? null
              : switch (atual.situacao) {
                  SituacaoPreco.confirmado when atual.confirmacoes >= 3 => ('Confiança alta', Tema.recente),
                  SituacaoPreco.confirmado => ('Confiança média', Tema.recente),
                  SituacaoPreco.oficial => ('Dado oficial', Tema.anp),
                  SituacaoPreco.estimado => ('Estimativa', Tema.estimativa),
                  SituacaoPreco.divergente => ('Envios divergentes', Tema.antigo),
                  SituacaoPreco.naoConfirmado => ('Aguardando confirmação', Tema.antigo),
                };

          return ListView(controller: rolagem, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
            Text('Contribuições', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text('${Produto.porId(widget.produtoId).nome} · ${widget.posto.resumo.nome}', style: tt.bodyLarge),
            const SizedBox(height: 16),
            if (atual != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(preco(atual.preco), style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      if (confianca != null)
                        Chip(
                          label: Text(confianca.$1),
                          labelStyle: TextStyle(color: confianca.$2, fontWeight: FontWeight.w700),
                          backgroundColor: confianca.$2.withValues(alpha: 0.12),
                          side: BorderSide.none,
                        ),
                    ]),
                    const SizedBox(height: 6),
                    Text(_explicacao(atual), style: tt.bodyMedium),
                  ]),
                ),
              ),
            if (confirmadas.isNotEmpty) ...[
              _titulo(context, 'VALOR CONFIRMADO · ${confirmadas.length} ENVIOS'),
              Card(child: Column(children: [for (final c in confirmadas) _LinhaContribuicao(c)])),
            ],
            if (outras.isNotEmpty) ...[
              _titulo(context, 'OUTRAS VARIAÇÕES REPORTADAS'),
              Card(child: Column(children: [for (final c in outras) _LinhaContribuicao(c, apagada: true)])),
            ],
            if (contrib.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Ninguém enviou este preço nos últimos 7 dias.', style: tt.bodyMedium?.copyWith(color: cs.outline)),
              ),
            _titulo(context, 'DADO OFICIAL'),
            Card(
              color: Tema.anp.withValues(alpha: 0.08),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.account_balance_outlined)),
                title: const Text('Pesquisa ANP', style: TextStyle(color: Tema.anp, fontWeight: FontWeight.w700)),
                subtitle: Text(anp == null
                    ? 'Este posto não entrou na amostra da ANP nos últimos 4 meses.'
                    : 'Semana de ${data(anp.dia)} · usada quando os envios divergem'),
                trailing: anp == null
                    ? null
                    : Text(preco(anp.preco), style: tt.titleMedium?.copyWith(color: Tema.anp, fontWeight: FontWeight.w800)),
              ),
            ),
          ]);
        },
      ),
    );
  }

  String _explicacao(PrecoAtual p) => switch (p.situacao) {
        SituacaoPreco.confirmado =>
          '${p.confirmacoes} usuários confirmaram esse valor. É o preço exibido para este posto.',
        SituacaoPreco.naoConfirmado => 'Enviado ${tempoRelativo(p.atualizadoEm)} e ainda sem confirmação de outra pessoa.',
        SituacaoPreco.divergente => 'Os envios recentes não concordam entre si. Por isso vale o dado da ANP.',
        SituacaoPreco.oficial => 'Não há envio recente da comunidade. Vale a última pesquisa da ANP.',
        SituacaoPreco.estimado =>
          'Nenhuma fonte para este posto. Estimativa pela mediana dos postos pesquisados mais próximos, a ${distancia(p.distanciaKm)}.',
      };

  Widget _titulo(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(t,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 0.8,
                  color: Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w700,
                )),
      );
}

class _LinhaContribuicao extends StatelessWidget {
  final Contribuicao c;
  final bool apagada;
  const _LinhaContribuicao(this.c, {this.apagada = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iniciais = c.autor.split(' ').where((e) => e.isNotEmpty).take(2).map((e) => e[0]).join().toUpperCase();
    final status = switch (c.status) {
      'confirmado' => '',
      'pendente' => ' · aguardando confirmação',
      'contestado' => ' · contrariado',
      'expirado' => ' · sem outras confirmações',
      _ => '',
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: apagada ? cs.surfaceContainerHighest : cs.primaryContainer,
        child: Text(iniciais, style: TextStyle(color: apagada ? cs.outline : cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
      ),
      title: Text(c.souEu ? '${c.autor} (você)' : c.autor, style: TextStyle(color: apagada ? cs.outline : null)),
      subtitle: Text('${tempoRelativo(c.criadoEm)}$status${c.editado ? ' · corrigido à mão' : ''}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(message: 'Lido de uma foto do painel', child: Icon(Icons.photo_camera_outlined, color: cs.outline, size: 20)),
        const SizedBox(width: 8),
        Text(preco(c.preco),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: apagada ? cs.outline : null)),
      ]),
    );
  }
}
