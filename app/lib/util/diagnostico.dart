import 'package:flutter/foundation.dart';

/// Guarda o último erro não tratado para o aviso do mapa mostrar a causa técnica quando o mapa nativo não abre.
class Diagnostico {
  static String? ultimoErro;

  static void instalar() {
    final anteriorFlutter = FlutterError.onError;
    FlutterError.onError = (detalhes) {
      ultimoErro = _resumo(detalhes.exceptionAsString());
      anteriorFlutter?.call(detalhes);
    };
    final anteriorPlataforma = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (erro, pilha) {
      ultimoErro = _resumo(erro.toString());
      return anteriorPlataforma?.call(erro, pilha) ?? false;
    };
  }

  static String _resumo(String texto) {
    final limpo = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
    return limpo.length > 240 ? '${limpo.substring(0, 240)}…' : limpo;
  }
}
