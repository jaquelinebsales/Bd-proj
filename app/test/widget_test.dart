import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gasprice/modelos/modelos.dart';
import 'package:gasprice/widgets/comuns.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  Widget emTela(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

  testWidgets('linha de preço mostra valor, origem e selo da comunidade', (tester) async {
    await tester.pumpWidget(emTela(LinhaPreco(
      produtoId: 1,
      preco: PrecoAtual(
        produtoId: 1,
        preco: 5.99,
        fonte: FontePreco.comunidade,
        situacao: SituacaoPreco.confirmado,
        atualizadoEm: DateTime.now().subtract(const Duration(hours: 2)),
        confirmacoes: 3,
      ),
    )));
    expect(find.text('Gasolina comum'), findsOneWidget);
    expect(find.textContaining('5,99'), findsOneWidget);
    expect(find.textContaining('comunidade'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('preço da ANP mostra a semana da pesquisa e o selo ANP', (tester) async {
    await tester.pumpWidget(emTela(LinhaPreco(
      produtoId: 3,
      preco: PrecoAtual(
        produtoId: 3,
        preco: 4.29,
        fonte: FontePreco.anp,
        situacao: SituacaoPreco.oficial,
        atualizadoEm: DateTime(2026, 9, 21),
      ),
    )));
    expect(find.textContaining('Pesquisa ANP'), findsOneWidget);
    expect(find.text('ANP'), findsOneWidget);
  });

  testWidgets('estimativa aparece com "≈" e margem de erro', (tester) async {
    await tester.pumpWidget(emTela(LinhaPreco(
      produtoId: 1,
      preco: PrecoAtual(
        produtoId: 1,
        preco: 6.14,
        fonte: FontePreco.estimativa,
        situacao: SituacaoPreco.estimado,
        atualizadoEm: DateTime.now(),
        margem: 0.29,
        distanciaKm: 26.1,
      ),
    )));
    expect(find.textContaining('≈'), findsOneWidget);
    expect(find.textContaining('Estimativa · erro médio'), findsOneWidget);
    expect(find.textContaining('0,29'), findsOneWidget);
    expect(find.text('ESTIMATIVA'), findsOneWidget);
  });

  testWidgets('combustível sem preço mostra só "Sem preço"', (tester) async {
    await tester.pumpWidget(emTela(const LinhaPreco(produtoId: 6)));
    expect(find.text('Sem preço'), findsOneWidget);
  });
}
