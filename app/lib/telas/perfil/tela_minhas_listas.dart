import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';

/// Todos os preços que a conta enviou (aberto pelo card "preços enviados" do perfil).
class TelaMeusEnvios extends StatelessWidget {
  const TelaMeusEnvios({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return _ListaPaginada(
      titulo: 'Preços enviados',
      // só as duas últimas semanas: a lista fica curta e atual
      dias: 14,
      aviso: 'Envios dos últimos 14 dias',
      carregar: (offset) => Api.instancia.meusEnvios(offset: offset),
      vazio: const EstadoVazio(
        icone: Icons.photo_camera_outlined,
        titulo: 'Nenhum preço enviado nos últimos 14 dias',
        texto: 'Na página de um posto, toque em Atualizar preços e fotografe o painel.',
      ),
      cartao: (context, e) {
        final status = e['status'].toString();
        return CartaoLinha(
          aoTocar: () => context.push('/posto/${e['posto_id']}'),
          titulo: nomeExibicao(e['posto'].toString()),
          detalhe: '${Produto.porId((e['produto_id'] as num).toInt()).nome} · ${statusDoEnvio(status)} · '
              '${tempoRelativo(DateTime.parse(e['criado_em'].toString()).toLocal())}',
          fim: Text(
            preco((e['preco'] as num).toDouble()),
            style: tt.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: status == 'contestado' ? cs.error : null,
            ),
          ),
        );
      },
    );
  }
}

/// Todas as avaliações da conta (aberto pelo card "avaliações" do perfil).
class TelaMinhasAvaliacoes extends StatelessWidget {
  const TelaMinhasAvaliacoes({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return _ListaPaginada(
      titulo: 'Minhas avaliações',
      carregar: (offset) => Api.instancia.minhasAvaliacoes(offset: offset),
      vazio: const EstadoVazio(
        icone: Icons.reviews_outlined,
        titulo: 'Nenhuma avaliação ainda',
        texto: 'Na página de um posto, toque em Avaliar para dar a sua nota.',
      ),
      cartao: (context, a) {
        final comentario = a['comentario'];
        final quando = a['criado_em'] == null ? null : DateTime.parse(a['criado_em'].toString()).toLocal();
        final uteis = (a['votos_uteis'] as num?)?.toInt() ?? 0;
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/posto/${a['posto_id']}'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(nomeExibicao(a['posto'].toString()), style: tt.titleSmall)),
                  if (quando != null) Text(tempoRelativo(quando), style: tt.bodySmall),
                ]),
                const SizedBox(height: 4),
                Estrelas((a['nota'] as num).toDouble()),
                if (comentario != null) ...[const SizedBox(height: 8), Text(comentario.toString(), style: tt.bodyMedium)],
                if (uteis > 0) ...[
                  const SizedBox(height: 8),
                  Text(uteis == 1 ? '1 pessoa achou útil' : '$uteis pessoas acharam útil', style: tt.bodySmall),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Situação de um preço enviado, como aparece para quem enviou
String statusDoEnvio(String s) => switch (s) {
      'confirmado' => 'confirmado',
      'pendente' => 'aguardando',
      'contestado' => 'contrariado',
      'expirado' => 'sem confirmação',
      _ => s,
    };

/// Lista que carrega de 50 em 50 ao chegar perto do fim, em colunas no tablet. Com [dias], mostra só os itens
/// desse período (a lista vem do mais recente ao mais antigo: o primeiro item mais antigo encerra a carga).
class _ListaPaginada extends StatefulWidget {
  final String titulo;
  final Future<List<Map<String, dynamic>>> Function(int offset) carregar;
  final Widget vazio;
  final Widget Function(BuildContext, Map<String, dynamic>) cartao;
  final int? dias;
  final String? aviso;
  const _ListaPaginada({
    required this.titulo,
    required this.carregar,
    required this.vazio,
    required this.cartao,
    this.dias,
    this.aviso,
  });

  @override
  State<_ListaPaginada> createState() => _ListaPaginadaState();
}

class _ListaPaginadaState extends State<_ListaPaginada> {
  static const _pagina = 50;
  final _itens = <Map<String, dynamic>>[];
  int _carregados = 0;
  bool _carregando = false;
  bool _fim = false;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _mais();
  }

  Future<void> _mais() async {
    if (_carregando || _fim) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final offset = _carregados;
      final novos = await widget.carregar(offset);
      if (!mounted) return;
      final dias = widget.dias;
      final limite = dias == null ? null : DateTime.now().subtract(Duration(days: dias));
      final noPeriodo = limite == null
          ? novos
          : novos.where((e) => DateTime.parse(e['criado_em'].toString()).isAfter(limite)).toList();
      setState(() {
        _carregados = offset + novos.length;
        _itens.addAll(noPeriodo);
        _fim = novos.length < _pagina || noPeriodo.length < novos.length;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _recarregar() async {
    setState(() {
      _itens.clear();
      _carregados = 0;
      _fim = false;
    });
    await _mais();
  }

  @override
  Widget build(BuildContext context) {
    Widget corpo;
    if (_erro != null && _itens.isEmpty) {
      corpo = EstadoErro(_erro!, _mais);
    } else if (_itens.isEmpty && _carregando) {
      corpo = const Center(child: CircularProgressIndicator());
    } else if (_itens.isEmpty) {
      corpo = widget.vazio;
    } else {
      corpo = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _mais();
          return false;
        },
        child: RefreshIndicator(
          onRefresh: _recarregar,
          child: GradeDeCartoes(
            colunas: colunasDeCartoes(context),
            padding: const EdgeInsets.all(16),
            quantidade: _itens.length,
            cartao: (context, i) => widget.cartao(context, _itens[i]),
          ),
        ),
      );
    }
    final aviso = widget.aviso;
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: LarguraMaxima(
        maxima: larguraListas,
        child: aviso == null || _itens.isEmpty
            ? corpo
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(aviso,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                Expanded(child: corpo),
              ]),
      ),
    );
  }
}
