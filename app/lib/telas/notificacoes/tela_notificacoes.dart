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
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final n = lista[i];
                final caiu = n.precoNovo < n.precoAnterior;
                final produto = Produto.porId(n.produtoId).nome;
                return Card(
                  color: n.lida ? null : cs.secondaryContainer,
                  child: ListTile(
                    onTap: () => context.push('/posto/${n.postoId}'),
                    leading: CircleAvatar(
                      backgroundColor: (caiu ? cs.primary : cs.error).withValues(alpha: 0.15),
                      child: Icon(caiu ? Icons.trending_down : Icons.trending_up, color: caiu ? cs.primary : cs.error),
                    ),
                    title: Text(n.nomePosto ?? 'Posto favorito'),
                    subtitle: Text(
                      '$produto ${caiu ? 'caiu' : 'subiu'} de ${preco(n.precoAnterior)} para ${preco(n.precoNovo)} · '
                      '${tempoRelativo(n.criadoEm)}',
                    ),
                    trailing: Text(preco(n.precoNovo), style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
