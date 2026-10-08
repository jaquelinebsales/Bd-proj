import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gasprice/modelos/modelos.dart';
import 'package:gasprice/tema.dart';
import 'package:gasprice/widgets/comuns.dart';

/// Contraste WCAG entre duas cores opacas.
double contraste(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('paleta Asfalto: marca e fundos fixos nos dois temas', () {
    final claro = Tema.claro().colorScheme, escuro = Tema.escuro().colorScheme;
    expect(claro.primary, const Color(0xFF2C3E57));
    expect(claro.primaryContainer, const Color(0xFFD9E2EE));
    expect(escuro.surface, const Color(0xFF101317));
    expect(escuro.surfaceContainer, const Color(0xFF1E242C));
    expect(escuro.primary, const Color(0xFFA9C3E6));
    expect(escuro.onPrimary, const Color(0xFF0E2340));
  });

  test('as cores do preço trocam com o tema', () {
    expect(Tema.claro().extension<CoresPreco>(), same(CoresPreco.claro));
    expect(Tema.escuro().extension<CoresPreco>(), same(CoresPreco.escuro));
  });

  test('textos passam de 4,5:1 sobre o fundo, as barras e os cartões nos dois temas', () {
    for (final tema in [Tema.claro(), Tema.escuro()]) {
      final cs = tema.colorScheme;
      final cores = tema.extension<CoresPreco>()!;
      for (final fundo in [cs.surface, cs.surfaceContainerLow, cs.surfaceContainer]) {
        for (final (nome, cor) in [
          ('texto', cs.onSurface),
          ('texto secundário', cs.onSurfaceVariant),
          ('contorno usado em texto', cs.outline),
          ('marca', cs.primary),
          ('ANP', cores.anp),
          ('estimativa', cores.estimativa),
        ]) {
          expect(contraste(cor, fundo), greaterThanOrEqualTo(4.5),
              reason: '$nome sobre #${fundo.toARGB32().toRadixString(16)} no tema ${tema.brightness.name}');
        }
      }
      expect(contraste(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5));
      expect(contraste(cs.onSecondaryContainer, cs.secondaryContainer), greaterThanOrEqualTo(4.5));
      expect(contraste(cs.onTertiaryContainer, cs.tertiaryContainer), greaterThanOrEqualTo(4.5));
      // Aviso de localização na família da marca, sem o lilás gerado pelo Material
      expect(cs.tertiaryContainer, cs.secondaryContainer);
    }
  });

  test('pinos preenchidos: número branco legível sobre o verde e o âmbar', () {
    expect(contraste(Colors.white, CoresPreco.claro.recente), greaterThanOrEqualTo(4.5));
    expect(contraste(Colors.white, CoresPreco.claro.antigo), greaterThanOrEqualTo(4.5));
  });

  testWidgets('bolinha de idade usa o verde claro no tema escuro', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: Tema.escuro(), home: const Scaffold(body: PontoFrescor(Frescor.recente))));
    final bolinha = tester.widget<Container>(find.descendant(of: find.byType(PontoFrescor), matching: find.byType(Container)));
    expect((bolinha.decoration! as BoxDecoration).color, CoresPreco.escuro.recente);
  });
}
