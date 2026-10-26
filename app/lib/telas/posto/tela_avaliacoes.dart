import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';
import 'tela_posto.dart';

/// Avaliações do posto: distribuição das notas, recentes ou mais relevantes.
class TelaAvaliacoes extends StatefulWidget {
  final int postoId;
  const TelaAvaliacoes({super.key, required this.postoId});
  @override
  State<TelaAvaliacoes> createState() => _TelaAvaliacoesState();
}

class _TelaAvaliacoesState extends State<TelaAvaliacoes> {
  String _ordem = 'recentes';
  final _lista = <Avaliacao>[];
  bool _carregando = false;
  bool _fim = false;
  Object? _erro;
  PostoDetalhe? _posto;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  Future<void> _recarregar() async {
    _lista.clear();
    _fim = false;
    try {
      _posto = await Api.instancia.detalhe(widget.postoId);
    } catch (_) {}
    await _maisItens();
  }

  Future<void> _maisItens() async {
    if (_carregando || _fim) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final novos = await Api.instancia.avaliacoes(widget.postoId, ordem: _ordem, offset: _lista.length);
      _lista.addAll(novos);
      _fim = novos.length < 20;
    } catch (e) {
      _erro = e;
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _votar(Avaliacao a) async {
    if (!await exigirLogin(context, 'Para marcar uma avaliação como útil, entre na sua conta.')) return;
    try {
      await Api.instancia.votarUtil(a.id, !a.votei);
      final i = _lista.indexOf(a);
      setState(() => _lista[i] = Avaliacao(
            id: a.id,
            autor: a.autor,
            nota: a.nota,
            comentario: a.comentario,
            votosUteis: a.votosUteis + (a.votei ? -1 : 1),
            criadoEm: a.criadoEm,
            minha: a.minha,
            votei: !a.votei,
          ));
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    }
  }

  Future<void> _avaliar() async {
    if (!await exigirLogin(context, 'Para avaliar postos, entre na sua conta.')) return;
    if (!mounted) return;
    final salvou = await context.push<bool>('/posto/${widget.postoId}/avaliar');
    if (salvou == true) {
      Api.instancia.invalidarPosto(widget.postoId);
      _recarregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_posto?.resumo.nome ?? 'Avaliações')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _avaliar,
        icon: const Icon(Icons.rate_review_outlined),
        label: Text(_posto?.minhaAvaliacao == null ? 'Avaliar' : 'Editar minha avaliação'),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _maisItens();
          return false;
        },
        child: RefreshIndicator(
          onRefresh: _recarregar,
          // No tablet em paisagem: resumo das notas à esquerda, avaliações em duas colunas à direita
          child: ColunasAdaptaveis(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            flexDireita: 2,
            esquerda: [
              if (_posto != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ResumoNotas(
                      media: _posto!.resumo.notaMedia,
                      total: _posto!.resumo.totalAvaliacoes,
                      distribuicao: _posto!.distribuicaoNotas,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'recentes', label: Text('Mais recentes')),
                  ButtonSegment(value: 'relevantes', label: Text('Mais úteis')),
                ],
                selected: {_ordem},
                onSelectionChanged: (s) {
                  _ordem = s.first;
                  _recarregar();
                },
              ),
              const SizedBox(height: 12),
            ],
            direita: [
              if (_erro != null) EstadoErro(_erro!, _recarregar),
              if (_lista.isEmpty && !_carregando && _erro == null)
                const EstadoVazio(
                  icone: Icons.reviews_outlined,
                  titulo: 'Nenhuma avaliação ainda',
                  texto: 'Seja a primeira pessoa a avaliar este posto.',
                ),
              LinhasDeCartoes(
                colunas: tamanhoDe(context) == Tamanho.expandido ? 2 : 1,
                cartoes: [
                  for (final a in _lista)
                    Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(a.minha ? '${a.autor} (você)' : a.autor, style: tt.titleSmall)),
                          Text(tempoRelativo(a.criadoEm), style: tt.bodySmall),
                        ]),
                        const SizedBox(height: 4),
                        Estrelas(a.nota.toDouble()),
                        if (a.comentario != null) ...[const SizedBox(height: 8), Text(a.comentario!, style: tt.bodyMedium)],
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: a.minha ? null : () => _votar(a),
                            icon: Icon(a.votei ? Icons.thumb_up : Icons.thumb_up_outlined, size: 18),
                            label: Text(a.votosUteis > 0 ? 'Útil (${a.votosUteis})' : 'Útil'),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
              if (_carregando) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }
}
