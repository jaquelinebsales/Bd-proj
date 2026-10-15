import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Conta de teste criada pelo testes_android/executar.py no servidor real e apagada no fim.
const qaEmail = String.fromEnvironment('QA_EMAIL');
const qaSenha = String.fromEnvironment('QA_SENHA');
const qaSenhaNova = String.fromEnvironment('QA_SENHA_NOVA');
const qaNome = String.fromEnvironment('QA_NOME', defaultValue: 'Qa Teste');

const critica = 'Crítica', alta = 'Alta', media = 'Média', baixa = 'Baixa';

class Falha implements Exception {
  final String mensagem;
  Falha(this.mensagem);
  @override
  String toString() => mensagem;
}

/// Caso que não dá para executar automaticamente (câmera, app externo): entra como NOT TESTED com o motivo.
class NaoTestado implements Exception {
  final String motivo;
  NaoTestado(this.motivo);
}

void confirmar(bool condicao, String mensagem) {
  if (!condicao) throw Falha(mensagem);
}

/// Cada caso imprime uma linha QA_RESULTADO com JSON, que o executar.py grava na planilha da auditoria.
/// QA_CAPTURA pede uma captura da tela ao executar.py (adb screencap, que pega também o mapa nativo);
/// QA_ADB pede um comando no aparelho (permissões, trazer o app de volta).
class Qa {
  final WidgetTester t;
  Qa(this.t);
  int _n = 0;
  int falhas = 0;

  Future<void> caso({
    required String modulo,
    required String tela,
    required String tipo,
    required String cenario,
    String precondicoes = '-',
    required String passos,
    String entrada = '-',
    required String esperado,
    String severidade = media,
    bool capturar = true,
    required Future<String> Function() corpo,
  }) async {
    final id = 'EMU-${(++_n).toString().padLeft(3, '0')}';
    final inicio = DateTime.now();
    String status, obtido;
    try {
      obtido = await corpo();
      status = 'PASS';
    } on NaoTestado catch (e) {
      status = 'NOT TESTED';
      obtido = e.motivo;
    } catch (e) {
      status = 'FAIL';
      obtido = e.toString();
    }
    // Erros do Flutter durante o caso (estouro de layout, exceção no build) também reprovam
    final erros = <String>[];
    for (Object? ex = t.takeException(); ex != null; ex = t.takeException()) {
      erros.add(ex.toString().split('\n').first);
    }
    if (erros.isNotEmpty) {
      status = 'FAIL';
      obtido = '$obtido | Erro do Flutter: ${erros.join(' | ')}';
    }
    if (status == 'FAIL') falhas++;
    final captura = capturar ? await capturarTela(id) : null;
    // ignore: avoid_print
    print('QA_RESULTADO:${jsonEncode({
      'id': id,
      'modulo': modulo,
      'tela': tela,
      'tipo': tipo,
      'cenario': cenario,
      'precondicoes': precondicoes,
      'passos': passos,
      'entrada': entrada,
      'esperado': esperado,
      'obtido': obtido,
      'status': status,
      'severidade': severidade,
      'captura': captura,
      'duracao_ms': DateTime.now().difference(inicio).inMilliseconds,
    })}');
  }

  Future<String> capturarTela(String nome) async {
    await t.pump(const Duration(milliseconds: 300));
    // ignore: avoid_print
    print('QA_CAPTURA:$nome');
    await aguardar(const Duration(milliseconds: 2500));
    return nome;
  }

  Future<void> adb(String comando, {Duration espera = const Duration(seconds: 5)}) async {
    // ignore: avoid_print
    print('QA_ADB:$comando');
    await aguardar(espera);
  }

  /// Espera o tempo real passar desenhando quadros (rede, animações e o mapa nativo continuam).
  Future<void> aguardar(Duration d) async {
    final fim = DateTime.now().add(d);
    while (DateTime.now().isBefore(fim)) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<Finder> esperar(Finder f, {Duration limite = const Duration(seconds: 20), String? oque}) async {
    final fim = DateTime.now().add(limite);
    while (true) {
      await t.pump(const Duration(milliseconds: 200));
      if (f.evaluate().isNotEmpty) return f;
      if (DateTime.now().isAfter(fim)) {
        throw Falha('Não apareceu em ${limite.inSeconds} s: ${oque ?? f.describeMatch(Plurality.one)}');
      }
    }
  }

  Future<void> esperarSumir(Finder f, {Duration limite = const Duration(seconds: 20), String? oque}) async {
    final fim = DateTime.now().add(limite);
    while (true) {
      await t.pump(const Duration(milliseconds: 200));
      if (f.evaluate().isEmpty) return;
      if (DateTime.now().isAfter(fim)) {
        throw Falha('Continuou na tela depois de ${limite.inSeconds} s: ${oque ?? f.describeMatch(Plurality.one)}');
      }
    }
  }

  bool existe(Finder f) => f.evaluate().isNotEmpty;

  /// Acha o widget, rolando a lista vertical da tela se ele ainda não foi construído.
  Future<Finder> achar(Finder f, {Duration limite = const Duration(seconds: 15)}) async {
    try {
      return await esperar(f, limite: const Duration(seconds: 3));
    } on Falha {
      final rolaveis = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
      if (rolaveis.evaluate().isEmpty) return esperar(f, limite: limite);
      await t.scrollUntilVisible(f, 250, scrollable: rolaveis.last, maxScrolls: 40);
      return f;
    }
  }

  Future<void> tocar(Finder f, {Duration limite = const Duration(seconds: 20)}) async {
    await achar(f, limite: limite);
    await t.ensureVisible(f.first);
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(f.first, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> escrever(Finder campo, String texto) async {
    await tocar(campo);
    await t.enterText(campo.first, texto);
    await t.pump(const Duration(milliseconds: 200));
  }

  /// Botão voltar do Android: fecha folha, diálogo ou tela.
  Future<void> voltar() async {
    await t.binding.handlePopRoute();
    await aguardar(const Duration(milliseconds: 700));
  }

  GoRouter get rotas => GoRouter.of(t.element(find.byType(Navigator).first));

  /// Volta ao estado conhecido entre blocos de casos, para uma falha não arrastar as seguintes.
  Future<void> irPara(String rota) async {
    for (var i = 0; i < 6 && rotas.canPop(); i++) {
      rotas.pop();
      await t.pump(const Duration(milliseconds: 300));
    }
    rotas.go(rota);
    await aguardar(const Duration(milliseconds: 1200));
  }

  /// Mensagem de rodapé (SnackBar) com o texto, ou parte dele.
  Future<String> esperarMensagem(String trecho, {Duration limite = const Duration(seconds: 15)}) async {
    final f = find.descendant(of: find.byType(SnackBar), matching: find.textContaining(trecho));
    await esperar(f, limite: limite, oque: 'mensagem "$trecho"');
    return (t.widget<Text>(f.first)).data ?? trecho;
  }

  String? mensagemAtual() {
    final f = find.descendant(of: find.byType(SnackBar), matching: find.byType(Text));
    return f.evaluate().isEmpty ? null : t.widget<Text>(f.first).data;
  }

  Size get tela => t.view.physicalSize / t.view.devicePixelRatio;
}
