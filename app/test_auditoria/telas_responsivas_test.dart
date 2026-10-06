// Auditoria de responsividade: abre cada rota do app em vários tamanhos de tela e com fonte ampliada,
// e registra estouros de layout e exceções. Roda no modo demonstração, com as fontes reais (Roboto).
//
//   flutter test test_auditoria --dart-define=DEMO=true
//   flutter test test_auditoria --dart-define=DEMO=true --dart-define=DEMO_LOGADO=true
//
// Cada caso imprime uma linha "AUDITORIA|{json}" que o script scripts/auditoria/t_telas.py transforma em linhas da matriz.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gasprice/app.dart';
import 'package:gasprice/config.dart';
import 'package:gasprice/servicos/favoritos.dart';
import 'package:gasprice/servicos/preferencias.dart';
import 'package:gasprice/servicos/sessao.dart';
import 'package:gasprice/tema.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rotas = <(String, String)>[
  ('/', 'Mapa'),
  ('/buscar', 'Busca'),
  ('/favoritos', 'Favoritos'),
  ('/perfil', 'Perfil'),
  ('/boas-vindas', 'Boas-vindas'),
  ('/posto/1', 'Posto'),
  ('/posto/4', 'Posto com localização aproximada'),
  ('/posto/6', 'Posto sem local e com estimativa'),
  ('/posto/1/historico?produto=1', 'Histórico'),
  ('/posto/1/avaliacoes', 'Avaliações'),
  ('/posto/1/avaliar', 'Avaliar'),
  ('/posto/1/enviar', 'Enviar preços'),
  ('/posto/4/posicao', 'Estou neste posto'),
  ('/entrar', 'Entrar'),
  ('/cadastro', 'Criar conta'),
  ('/recuperar-senha', 'Recuperar senha'),
  ('/nova-senha', 'Nova senha'),
  ('/verificar-email?email=carla.m%40exemplo.com', 'Confirme seu e-mail'),
  ('/perfil/editar', 'Alterar dados'),
  ('/perfil/senha', 'Alterar senha'),
  ('/pontos', 'Meus pontos'),
  ('/ranking', 'Ranking'),
  ('/notificacoes', 'Avisos de preço'),
  ('/sobre', 'Sobre'),
];

const tamanhos = <(double, double, double, String)>[
  (320, 568, 1.0, 'Celular pequeno 320×568'),
  (360, 800, 1.0, 'Celular 360×800'),
  (412, 915, 1.0, 'Celular grande 412×915'),
  (360, 800, 1.3, 'Celular 360×800 com fonte 130%'),
  (360, 800, 2.0, 'Celular 360×800 com fonte 200%'),
  (800, 1280, 1.0, 'Tablet em pé 800×1280'),
  (1280, 800, 1.0, 'Tablet deitado 1280×800'),
];

Future<void> carregarFontes() async {
  // flutter_tester fica em <flutter>/bin/cache/artifacts/engine/<plataforma>/; as fontes, em artifacts/material_fonts
  final motor = File(Platform.resolvedExecutable).parent;
  final pasta = Directory('${motor.parent.parent.path}${Platform.pathSeparator}material_fonts');
  if (!pasta.existsSync()) return;
  Future<void> familia(String nome, List<String> arquivos) async {
    final f = FontLoader(nome);
    for (final a in arquivos) {
      final arq = File('${pasta.path}${Platform.pathSeparator}$a');
      if (arq.existsSync()) f.addFont(Future.value(ByteData.view(arq.readAsBytesSync().buffer)));
    }
    await f.load();
  }

  await familia('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-light.ttf', 'roboto-black.ttf']);
  await familia('MaterialIcons', ['materialicons-regular.otf']);
}

/// Mensagem curta do erro e, quando houver, o arquivo e a linha do widget que o causou.
String descrever(FlutterErrorDetails d) {
  final local = RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(d.toString())?.group(0);
  return d.exceptionAsString().split('\n').take(2).join(' ') + (local == null ? '' : ' (em $local)');
}

String tipoDoErro(String m) {
  final t = m.toLowerCase();
  if (t.contains('overflowed')) return 'estouro';
  if (t.contains('was not laid out') || t.contains('constraints') || t.contains('infinite size') || t.contains('unbounded')) return 'layout';
  if (t.contains('httpexception') || t.contains('statuscode: 400') || t.contains('networkimage') || t.contains('socket') ||
      t.contains('tile')) {
    return 'rede (esperado no teste: sem internet)';
  }
  if (t.contains('missingpluginexception')) return 'ambiente de teste (plugin nativo indisponível)';
  return 'exceção';
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Fora de test/ o analisador não reconhece o arquivo como teste
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'viu_boas_vindas': true});
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    await carregarFontes();
    await Preferencias.carregar();
    Sessao.instancia.iniciar();
    await Favoritos.instancia.iniciar();
  });

  for (final t in tamanhos) {
    for (final r in rotas) {
      testWidgets('${r.$2} · ${t.$4}', (tester) async {
        tester.view.physicalSize = Size(t.$1, t.$2);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final erros = <String>[];
        final anterior = FlutterError.onError;
        FlutterError.onError = (d) => erros.add(descrever(d));

        // Abre direto na rota testada: os erros registrados são só desta tela
        final rotas0 = criarRotas(false)..go(r.$1);
        await tester.pumpWidget(MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: Tema.claro(),
          routerConfig: rotas0,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(t.$3)),
            child: child ?? const SizedBox(),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(seconds: 2));
        final rotaFinal = rotas0.routerDelegate.currentConfiguration.uri.toString();
        final textos = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('\n', ' ').trim())
            .where((s) => s.length > 2)
            .take(6)
            .toList();
        final excecao = tester.takeException();
        if (excecao != null) erros.add(excecao.toString().split('\n').first);

        // Evidência: imagem da tela quando há estouro de layout (gravada com --update-goldens)
        String? imagem;
        if (erros.any((e) => tipoDoErro(e) == 'estouro')) {
          final nome = '${Config.demoLogado ? 'logado' : 'visitante'}_${r.$2}_${t.$4}'
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
          imagem = 'evidencias/telas/$nome.png';
          FlutterError.onError = anterior;
          try {
            await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../documentacao/auditoria/$imagem'));
          } catch (_) {
            imagem = null;
          }
          FlutterError.onError = (d) => erros.add(descrever(d));
        }

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 30));
        FlutterError.onError = anterior;

        final classificados = [for (final e in erros) {'tipo': tipoDoErro(e), 'mensagem': e}];
        // ignore: avoid_print
        print('AUDITORIA|${jsonEncode({
              'rota': r.$1,
              'tela': r.$2,
              'tamanho': t.$4,
              'largura': t.$1,
              'altura': t.$2,
              'fonte': t.$3,
              'logado': Config.demoLogado,
              'rota_final': rotaFinal,
              'textos': textos,
              'erros': classificados,
              'imagem': imagem,
            })}');
      });
    }
  }
}
