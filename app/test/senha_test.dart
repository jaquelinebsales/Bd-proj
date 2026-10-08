import 'package:flutter_test/flutter_test.dart';
import 'package:gasprice/util/senha.dart';

void main() {
  test('senha completa é aceita', () {
    expect(validarSenha('Gasolina#2026'), isNull);
    expect(validarSenha('Aud1t-xyz'), isNull);
    expect(validarSenha('Ab1!efgh'), isNull, reason: 'exatamente 8 caracteres');
  });

  test('falta de qualquer exigência mostra sempre o texto padrão', () {
    for (final (senha, falta) in [
      ('Ab1#efg', 'menos de 8 caracteres'),
      ('abcdefg1#', 'letra maiúscula'),
      ('ABCDEFG1#', 'letra minúscula'),
      ('Abcdefgh#', 'número'),
      ('Abcdefgh1', 'caractere especial'),
      ('', 'campo vazio'),
    ]) {
      expect(validarSenha(senha), regraSenha, reason: falta);
    }
    expect(validarSenha(null), regraSenha);
  });

  test('espaço não conta como caractere especial', () {
    expect(validarSenha('Abcdefg 1'), regraSenha);
  });

  test('o texto padrão cita as quatro exigências', () {
    for (final parte in ['8 caracteres', 'maiúscula', 'minúscula', 'número', 'caractere especial']) {
      expect(regraSenha, contains(parte));
    }
  });
}
