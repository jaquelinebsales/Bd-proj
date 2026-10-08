import 'package:supabase_flutter/supabase_flutter.dart';

/// Erro do banco por tempo esgotado (statement timeout, código 57014). No plano gratuito do Supabase
/// isso acontece de vez em quando quando o servidor está ocupado; uma segunda tentativa costuma passar.
bool ehTempoEsgotado(Object erro) => erro is PostgrestException && erro.code == '57014';

/// Executa [f]; se falhar por tempo esgotado, espera um pouco e tenta mais uma vez.
/// Só para leituras: repetir uma escrita poderia gravar duas vezes.
Future<T> lerComNovaTentativa<T>(
  Future<T> Function() f, {
  bool Function(Object erro) repetirSe = ehTempoEsgotado,
  Duration espera = const Duration(milliseconds: 700),
}) async {
  try {
    return await f();
  } catch (e) {
    if (!repetirSe(e)) rethrow;
    await Future<void>.delayed(espera);
    return f();
  }
}
