import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/sessao.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';

/// Total e extrato de pontos. As regras de como ganhar e perder pontos ficam no ícone de informação.
class TelaPontos extends StatefulWidget {
  const TelaPontos({super.key});
  @override
  State<TelaPontos> createState() => _TelaPontosState();
}

class _TelaPontosState extends State<TelaPontos> {
  late Future<List<MovimentoPontos>> _extrato = Api.instancia.extratoPontos();

  static const _regras = [
    (Icons.verified_outlined, '+10', 'Envio confirmado por outra pessoa em até 24 horas'),
    (Icons.bolt_outlined, '+5', 'Primeiro envio em posto sem atualização há mais de 24 horas'),
    (Icons.looks_two_outlined, '×2', 'Em cidades onde a ANP não pesquisa preços'),
    (Icons.my_location_outlined, '+5', 'Posição de um posto confirmada por outra pessoa'),
    (Icons.report_outlined, '−5', 'Envio contrariado por outros usuários'),
    (Icons.timer_outlined, '200', 'Máximo de pontos ganhos por dia'),
  ];

  void _comoFunciona() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text('Como funciona', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final (icone, valor, texto) in _regras)
            ListTile(
              leading: Icon(icone, color: cs.primary),
              title: Text(texto),
              trailing: Text(valor, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final perfil = Sessao.instancia.perfil;
    return Scaffold(
      appBar: AppBar(title: const Text('Meus pontos'), actions: [
        IconButton(tooltip: 'Como funciona', onPressed: _comoFunciona, icon: const Icon(Icons.info_outline)),
      ]),
      body: LarguraMaxima(
        maxima: larguraListas,
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() => _extrato = Api.instancia.extratoPontos());
            await Sessao.instancia.carregarPerfil();
          },
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
            Card(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  Icon(Icons.stars_rounded, size: 48, color: cs.onPrimaryContainer),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${perfil?.pontos ?? 0} pontos',
                          style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
                      Text('Nível ${perfil?.nivel ?? '–'}', style: tt.bodyLarge?.copyWith(color: cs.onPrimaryContainer)),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            Text('Extrato', style: tt.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<MovimentoPontos>>(
              future: _extrato,
              builder: (context, snap) {
                if (snap.hasError) return EstadoErro(snap.error!, () => setState(() => _extrato = Api.instancia.extratoPontos()));
                if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                final lista = snap.data!;
                if (lista.isEmpty) {
                  return const EstadoVazio(
                    icone: Icons.photo_camera_outlined,
                    titulo: 'Nenhum ponto ainda',
                    texto: 'Envie a foto do painel de um posto. Quando alguém confirmar o mesmo preço, seus pontos aparecem aqui.',
                  );
                }
                return LinhasDeCartoes(
                  colunas: colunasDeCartoes(context),
                  cartoes: [
                    for (final m in lista)
                      CartaoLinha(
                        titulo: m.descricao,
                        detalhe: tempoRelativo(m.criadoEm),
                        fim: Text(
                          m.pontos > 0 ? '+${m.pontos}' : '${m.pontos}',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: m.pontos > 0 ? cs.primary : cs.error,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ]),
        ),
      ),
    );
  }
}
