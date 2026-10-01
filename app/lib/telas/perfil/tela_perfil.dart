import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modelos/modelos.dart';
import '../../servicos/notificacoes.dart';
import '../../servicos/sessao.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';

/// Perfil: dados, pontos, últimas atividades e opções da conta.
class TelaPerfil extends StatelessWidget {
  const TelaPerfil({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([Sessao.instancia, ServicoNotificacoes.instancia]),
        builder: (context, _) {
          final s = Sessao.instancia;
          if (!s.logado) return const _Visitante();
          return _Logado(perfil: s.perfil, email: s.usuario?.email ?? '');
        },
      );
}

class _Visitante extends StatelessWidget {
  const _Visitante();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: LarguraMaxima(
          maxima: 560,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const EstadoVazio(
              icone: Icons.person_add_alt_1_outlined,
              titulo: 'Contribua com a sua cidade',
              texto: 'Com uma conta você atualiza preços por foto, avalia postos, ganha pontos e recebe avisos '
                  'quando o preço do seu posto favorito mudar.',
            ),
            FilledButton(onPressed: () => context.push('/cadastro'), child: const Text('Criar conta')),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => context.push('/entrar'),
              child: const Text('Entrar'),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.leaderboard_outlined),
              title: const Text('Ranking da comunidade'),
              onTap: () => context.push('/ranking'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Sobre os dados e privacidade'),
              onTap: () => context.push('/sobre'),
            ),
          ]),
        ),
      );
}

class _Logado extends StatelessWidget {
  final ResumoPerfil? perfil;
  final String email;
  const _Logado({required this.perfil, required this.email});

  Future<void> _sair(BuildContext context) async {
    try {
      await Sessao.instancia.sair();
      if (context.mounted) mostrarMensagem(context, 'Você saiu da conta.');
    } catch (e) {
      if (context.mounted) mostrarMensagem(context, e);
    }
  }

  Future<void> _excluir(BuildContext context) async {
    final confirmado = await showDialog<bool>(context: context, builder: (_) => const _DialogoExcluirConta());
    if (confirmado != true || !context.mounted) return;
    try {
      await Sessao.instancia.excluirConta();
      if (context.mounted) {
        mostrarMensagem(context, 'Conta excluída.');
        context.go('/');
      }
    } catch (e) {
      if (context.mounted) mostrarMensagem(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = perfil;
    final naoLidas = ServicoNotificacoes.instancia.naoLidas;
    final iniciais = (p?.nome ?? email).split(' ').where((e) => e.isNotEmpty).take(2).map((e) => e[0].toUpperCase()).join();

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil'), actions: [
        IconButton(
          tooltip: 'Notificações',
          onPressed: () => context.push('/notificacoes'),
          icon: Badge(isLabelVisible: naoLidas > 0, label: Text('$naoLidas'), child: const Icon(Icons.notifications_outlined)),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: Sessao.instancia.carregarPerfil,
        child: LarguraMaxima(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: cs.primaryContainer,
                foregroundImage: p?.avatarUrl == null ? null : NetworkImage(p!.avatarUrl!),
                child: Text(iniciais, style: tt.headlineSmall?.copyWith(color: cs.onPrimaryContainer)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p?.nome ?? '…', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text(email, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  if (!Sessao.instancia.emailConfirmado)
                    Text('E-mail ainda não confirmado', style: tt.bodySmall?.copyWith(color: cs.error)),
                ]),
              ),
            ]),
            if (p?.bloqueadoAte != null && p!.bloqueadoAte!.isAfter(DateTime.now()))
              Card(
                color: cs.errorContainer,
                margin: const EdgeInsets.only(top: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Seus envios estão pausados até ${data(p.bloqueadoAte!)} porque vários preços foram contrariados por outros usuários.',
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Row(children: [
              _Numero(valor: '${p?.pontos ?? 0}', rotulo: 'pontos', aoTocar: () => context.push('/pontos')),
              _Numero(
                valor: p == null || p.posicaoRanking == 0 ? '–' : '${p.posicaoRanking}º',
                rotulo: 'no ranking',
                aoTocar: () => context.push('/ranking'),
              ),
              _Numero(valor: p?.nivel ?? '–', rotulo: 'nível', pequeno: true),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _Numero(valor: '${p?.totalEnvios ?? 0}', rotulo: 'preços enviados'),
              _Numero(valor: '${p?.enviosConfirmados ?? 0}', rotulo: 'confirmados'),
              _Numero(valor: '${p?.totalAvaliacoes ?? 0}', rotulo: 'avaliações'),
            ]),
            const SizedBox(height: 24),
            if (p != null && p.ultimosEnvios.isNotEmpty) ...[
              Text('Últimos preços enviados', style: tt.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  for (final e in p.ultimosEnvios.take(5))
                    ListTile(
                      onTap: () => context.push('/posto/${e['posto_id']}'),
                      title: Text(nomeExibicao(e['posto'].toString())),
                      subtitle: Text('${Produto.porId((e['produto_id'] as num).toInt()).nome} · '
                          '${_status(e['status'].toString())} · '
                          '${tempoRelativo(DateTime.parse(e['criado_em'].toString()).toLocal())}'),
                      trailing: Text(preco((e['preco'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            if (p != null && p.ultimasAvaliacoes.isNotEmpty) ...[
              Text('Últimas avaliações', style: tt.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  for (final a in p.ultimasAvaliacoes)
                    ListTile(
                      onTap: () => context.push('/posto/${a['posto_id']}'),
                      title: Text(nomeExibicao(a['posto'].toString())),
                      subtitle: a['comentario'] == null
                          ? null
                          : Text(a['comentario'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Estrelas((a['nota'] as num).toDouble(), tamanho: 14),
                    ),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Alterar dados'),
                  onTap: () => context.push('/perfil/editar'),
                ),
                ListTile(
                  leading: const Icon(Icons.password),
                  title: const Text('Alterar senha'),
                  onTap: () => context.push('/perfil/senha'),
                ),
                ListTile(
                  leading: const Icon(Icons.stars_outlined),
                  title: const Text('Extrato de pontos'),
                  onTap: () => context.push('/pontos'),
                ),
                ListTile(
                  leading: const Icon(Icons.leaderboard_outlined),
                  title: const Text('Ranking'),
                  onTap: () => context.push('/ranking'),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notificações'),
                  onTap: () => context.push('/notificacoes'),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Sobre os dados e privacidade'),
                  onTap: () => context.push('/sobre'),
                ),
                ListTile(leading: const Icon(Icons.logout), title: const Text('Sair da conta'), onTap: () => _sair(context)),
              ]),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _excluir(context),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Excluir minha conta'),
            ),
          ]),
        ),
      ),
    );
  }

  String _status(String s) => switch (s) {
        'confirmado' => 'confirmado',
        'pendente' => 'aguardando',
        'contestado' => 'contrariado',
        'expirado' => 'sem confirmação',
        _ => s,
      };
}

/// Confirmação da exclusão: exige digitar EXCLUIR para evitar toque acidental.
class _DialogoExcluirConta extends StatefulWidget {
  const _DialogoExcluirConta();
  @override
  State<_DialogoExcluirConta> createState() => _DialogoExcluirContaState();
}

class _DialogoExcluirContaState extends State<_DialogoExcluirConta> {
  final _confirmacao = TextEditingController();

  @override
  void dispose() {
    _confirmacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pode = _confirmacao.text.trim().toUpperCase() == 'EXCLUIR';
    return AlertDialog(
      title: const Text('Excluir conta?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Apagamos seu perfil, avaliações, favoritos e pontos. Os preços que você enviou continuam no '
            'histórico, sem o seu nome. Isso não pode ser desfeito.'),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmacao,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Digite EXCLUIR para confirmar'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            minimumSize: const Size(0, 40),
          ),
          onPressed: pode ? () => Navigator.pop(context, true) : null,
          child: const Text('Excluir conta'),
        ),
      ],
    );
  }
}

class _Numero extends StatelessWidget {
  final String valor;
  final String rotulo;
  final VoidCallback? aoTocar;
  final bool pequeno;
  const _Numero({required this.valor, required this.rotulo, this.aoTocar, this.pequeno = false});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(children: [
              Text(
                valor,
                style: (pequeno ? tt.titleMedium : tt.headlineSmall)?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(rotulo, style: tt.bodySmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }
}
