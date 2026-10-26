import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('window.parent')
external _Janela get _pai;

extension type _Janela._(JSObject _) implements JSObject {
  external void postMessage(JSAny? mensagem, String origemAlvo);
}

/// A página da demonstração pode estar em outro site (o app roda em processo separado para a moldura
/// animar sem disputar processamento); por isso o destino é qualquer origem. Os eventos não têm dado sensível.
void enviar(Map<String, Object?> dados) {
  try {
    _pai.postMessage(jsonEncode({'fonte': 'gasprice', ...dados}).toJS, '*');
  } catch (_) {}
}

@JS('window.__escalaApp')
external JSNumber? get _escalaApp;

@JS('window.__aoMudarEscala')
external set _aoMudarEscala(JSFunction funcao);

/// Escala em que a página mostra o aparelho (o script injetado pela demonstração a define; 1 fora dela)
double _escala() {
  try {
    final e = _escalaApp?.toDartDouble ?? 1;
    return e > 0 ? e : 1;
  } catch (_) {
    return 1;
  }
}

final escalaAtual = ValueNotifier<double>(_escala());

/// O script injetado chama window.__aoMudarEscala quando a página muda a escala
void iniciarEscala() {
  escalaAtual.value = _escala();
  _aoMudarEscala = (() => escalaAtual.value = _escala()).toJS;
}
