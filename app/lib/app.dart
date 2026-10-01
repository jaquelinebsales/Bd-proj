import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'config.dart';
import 'servicos/notificacoes.dart';
import 'servicos/sessao.dart';
import 'tema.dart';
import 'telas/auth/tela_cadastro.dart';
import 'telas/auth/tela_entrar.dart';
import 'telas/auth/tela_nova_senha.dart';
import 'telas/auth/tela_recuperar_senha.dart';
import 'telas/auth/tela_verificar_email.dart';
import 'telas/busca/tela_busca.dart';
import 'telas/envio/tela_enviar_precos.dart';
import 'telas/favoritos/tela_favoritos.dart';
import 'telas/inicio/tela_boas_vindas.dart';
import 'telas/mapa/tela_mapa.dart';
import 'telas/notificacoes/tela_notificacoes.dart';
import 'telas/perfil/tela_alterar_senha.dart';
import 'telas/perfil/tela_editar_perfil.dart';
import 'telas/perfil/tela_perfil.dart';
import 'telas/perfil/tela_pontos.dart';
import 'telas/perfil/tela_ranking.dart';
import 'telas/posto/tela_avaliacoes.dart';
import 'telas/posto/tela_avaliar.dart';
import 'telas/posto/tela_historico.dart';
import 'telas/posto/tela_posto.dart';
import 'telas/sobre/tela_sobre.dart';
import 'util/responsivo.dart';

class GaspriceApp extends StatefulWidget {
  final bool mostrarBoasVindas;
  const GaspriceApp({super.key, required this.mostrarBoasVindas});

  @override
  State<GaspriceApp> createState() => _GaspriceAppState();
}

class _GaspriceAppState extends State<GaspriceApp> {
  late final GoRouter _rotas = criarRotas(widget.mostrarBoasVindas);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'gasprice',
        debugShowCheckedModeBanner: false,
        theme: Tema.claro(),
        darkTheme: Tema.escuro(),
        routerConfig: _rotas,
        builder: (context, child) => Config.demo
            ? Banner(message: 'DEMO', location: BannerLocation.topEnd, child: child ?? const SizedBox())
            : child ?? const SizedBox(),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      );
}

int _id(GoRouterState s) => int.tryParse(s.pathParameters['id'] ?? '') ?? 0;

GoRouter criarRotas(bool boasVindas) => GoRouter(
      initialLocation: boasVindas ? '/boas-vindas' : '/',
      refreshListenable: Sessao.instancia,
      redirect: (context, estado) {
        final sessao = Sessao.instancia;
        if (sessao.recuperandoSenha && estado.matchedLocation != '/nova-senha') return '/nova-senha';
        const soLogado = ['/perfil/editar', '/perfil/senha', '/pontos', '/notificacoes'];
        if (!sessao.logado && soLogado.contains(estado.matchedLocation)) return '/entrar';
        const soDeslogado = ['/entrar', '/cadastro'];
        if (sessao.logado && soDeslogado.contains(estado.matchedLocation)) return '/perfil';
        return null;
      },
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, estado, navegacao) => Estrutura(navegacao: navegacao),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const TelaMapa())]),
            StatefulShellBranch(routes: [GoRoute(path: '/buscar', builder: (_, _) => const TelaBusca())]),
            StatefulShellBranch(routes: [GoRoute(path: '/favoritos', builder: (_, _) => const TelaFavoritos())]),
            StatefulShellBranch(routes: [GoRoute(path: '/perfil', builder: (_, _) => const TelaPerfil())]),
          ],
        ),
        GoRoute(path: '/boas-vindas', builder: (_, _) => const TelaBoasVindas()),
        GoRoute(path: '/posto/:id', builder: (_, s) => TelaPosto(postoId: _id(s))),
        GoRoute(
          path: '/posto/:id/historico',
          builder: (_, s) => TelaHistorico(postoId: _id(s), produtoId: int.tryParse(s.uri.queryParameters['produto'] ?? '') ?? 1),
        ),
        GoRoute(path: '/posto/:id/avaliacoes', builder: (_, s) => TelaAvaliacoes(postoId: _id(s))),
        GoRoute(path: '/posto/:id/avaliar', builder: (_, s) => TelaAvaliar(postoId: _id(s))),
        GoRoute(path: '/posto/:id/enviar', builder: (_, s) => TelaEnviarPrecos(postoId: _id(s))),
        GoRoute(path: '/entrar', builder: (_, _) => const TelaEntrar()),
        GoRoute(path: '/cadastro', builder: (_, _) => const TelaCadastro()),
        GoRoute(path: '/recuperar-senha', builder: (_, _) => const TelaRecuperarSenha()),
        GoRoute(path: '/nova-senha', builder: (_, _) => const TelaNovaSenha()),
        GoRoute(
          path: '/verificar-email',
          builder: (_, s) => TelaVerificarEmail(email: s.uri.queryParameters['email'] ?? ''),
        ),
        GoRoute(path: '/perfil/editar', builder: (_, _) => const TelaEditarPerfil()),
        GoRoute(path: '/perfil/senha', builder: (_, _) => const TelaAlterarSenha()),
        GoRoute(path: '/pontos', builder: (_, _) => const TelaPontos()),
        GoRoute(path: '/ranking', builder: (_, _) => const TelaRanking()),
        GoRoute(path: '/notificacoes', builder: (_, _) => const TelaNotificacoes()),
        GoRoute(path: '/sobre', builder: (_, _) => const TelaSobre()),
      ],
    );

/// Navegação principal: barra inferior no celular, trilho lateral no tablet.
class Estrutura extends StatelessWidget {
  final StatefulNavigationShell navegacao;
  const Estrutura({super.key, required this.navegacao});

  static const _destinos = [
    (Icons.map_outlined, Icons.map, 'Mapa'),
    (Icons.search, Icons.search, 'Buscar'),
    (Icons.favorite_outline, Icons.favorite, 'Favoritos'),
    (Icons.person_outline, Icons.person, 'Perfil'),
  ];

  void _ir(int i) => navegacao.goBranch(i, initialLocation: i == navegacao.currentIndex);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ServicoNotificacoes.instancia,
      builder: (context, _) {
        final naoLidas = ServicoNotificacoes.instancia.naoLidas;
        Widget icone(IconData i, int indice) =>
            indice == 3 && naoLidas > 0 ? Badge(label: Text('$naoLidas'), child: Icon(i)) : Icon(i);

        if (ehTablet(context)) {
          return Scaffold(
            body: Row(children: [
              NavigationRail(
                selectedIndex: navegacao.currentIndex,
                onDestinationSelected: _ir,
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Icon(Icons.local_gas_station_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
                ),
                destinations: [
                  for (var i = 0; i < _destinos.length; i++)
                    NavigationRailDestination(
                      icon: icone(_destinos[i].$1, i),
                      selectedIcon: icone(_destinos[i].$2, i),
                      label: Text(_destinos[i].$3),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: navegacao),
            ]),
          );
        }
        return Scaffold(
          body: navegacao,
          bottomNavigationBar: NavigationBar(
            selectedIndex: navegacao.currentIndex,
            onDestinationSelected: _ir,
            destinations: [
              for (var i = 0; i < _destinos.length; i++)
                NavigationDestination(
                  icon: icone(_destinos[i].$1, i),
                  selectedIcon: icone(_destinos[i].$2, i),
                  label: _destinos[i].$3,
                ),
            ],
          ),
        );
      },
    );
  }
}
