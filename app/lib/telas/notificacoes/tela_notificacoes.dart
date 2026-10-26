import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/notificacoes.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';

/// Avisos de mudança de preço nos postos favoritos.
class TelaNotificacoes extends StatefulWidget {
  const TelaNotificacoes({super.key});
  @override
  State<TelaNotificacoes> createState() => _TelaNotificacoesState();
}

class _TelaNotificacoesState extends State<TelaNotificacoes> {
  late Future<List<Notificacao>> _lista = Api.instancia.notificacoes();

  @override
  void initState() {
    super.initState();
    // Abrir a lista conta como leitura
    _lista.then((l) {
      if (l.any((n) => !n.lida)) ServicoNotificacoes.instancia.marcarTodasLidas();
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notificações'), actions: [
        IconButton(
          tooltip: 'Preferências de aviso',
          onPressed: () => context.push('/perfil/editar'),
          icon: const Icon(Icons.tune),
        ),
      ]),
      body: LarguraMaxima(
        maxima: larguraListas,
        child: FutureBuilder<List<Notificacao>>(
          future: _lista,
          builder: (context, snap) {
            if (snap.hasError) return EstadoErro(snap.error!, () => setState(() => _lista = Api.instancia.notificacoes()));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final lista = snap.data!;
            if (lista.isEmpty) {
              return const EstadoVazio(
                icone: Icons.notifications_none,
                titulo: 'Nenhum aviso',
                texto: 'Quando o preço de um posto favorito mudar pelo menos R\$ 0,05, o aviso aparece aqui.',
              );
            }
            return GradeDeCartoes(
              colunas: colunasDeCartoes(context),
              padding: const EdgeInsets.all(16),
              quantidade: lista.length,
              cartao: (context, i) {
                final n = lista[i];
                final caiu = n.precoNovo < n.precoAnterior;
                final produto = Produto.porId(n.produtoId).nome;
                return CartaoLinha(
                  cor: n.lida ? null : cs.secondaryContainer,
                  // Toque abre o gráfico do histórico de preço daquele combustível
                  aoTocar: () => context.push('/posto/${n.postoId}/historico?produto=${n.produtoId}'),
                  inicio: CircleAvatar(
                    backgroundColor: (caiu ? cs.primary : cs.error).withValues(alpha: 0.15),
                    child: Icon(caiu ? Icons.trending_down : Icons.trending_up, color: caiu ? cs.primary : cs.error),
                  ),
                  titulo: n.nomePosto ?? 'Posto favorito',
                  detalhe: produto,
                  fim: Text(preco(n.precoNovo), style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
