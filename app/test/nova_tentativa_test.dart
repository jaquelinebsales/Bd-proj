import 'package:flutter_test/flutter_test.dart';
import 'package:gasprice/util/nova_tentativa.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('tempo esgotado no banco: tenta de novo e devolve o resultado', () async {
    var chamadas = 0;
    final r = await lerComNovaTentativa(() async {
      chamadas++;
      if (chamadas == 1) throw const PostgrestException(message: 'canceling statement due to statement timeout', code: '57014');
      return 42;
    }, espera: Duration.zero);
    expect(r, 42);
    expect(chamadas, 2);
  });

  test('tempo esgotado duas vezes: o erro chega a quem chamou', () async {
    var chamadas = 0;
    await expectLater(
      lerComNovaTentativa(() async {
        chamadas++;
        throw const PostgrestException(message: 'timeout', code: '57014');
      }, espera: Duration.zero),
      throwsA(isA<PostgrestException>()),
    );
    expect(chamadas, 2, reason: 'só uma nova tentativa');
  });

  test('outros erros não são repetidos', () async {
    var chamadas = 0;
    await expectLater(
      lerComNovaTentativa(() async {
        chamadas++;
        throw const PostgrestException(message: 'permission denied', code: '42501');
      }, espera: Duration.zero),
      throwsA(isA<PostgrestException>()),
    );
    expect(chamadas, 1);
  });
}
