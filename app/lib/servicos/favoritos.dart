import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'sessao.dart';

/// Favoritos. Sem login ficam no aparelho; ao entrar, são enviados para a conta.
class Favoritos extends ChangeNotifier {
  Favoritos._();
  static final instancia = Favoritos._();

  static const _chave = 'favoritos_locais';
  Set<int> ids = {};
  bool _logadoAntes = false;

  Future<void> iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    ids = (prefs.getStringList(_chave) ?? []).map(int.parse).toSet();
    notifyListeners();
    Sessao.instancia.addListener(_aoMudarSessao);
    _aoMudarSessao();
  }

  Future<void> _aoMudarSessao() async {
    final logado = Sessao.instancia.logado;
    if (logado && !_logadoAntes) {
      _logadoAntes = true;
      // Envia os favoritos locais para a conta e passa a usar os da conta
      for (final id in ids.toList()) {
        try {
          await Api.instancia.favoritar(id, true);
        } catch (_) {}
      }
      await recarregar();
    } else if (!logado && _logadoAntes) {
      _logadoAntes = false;
      final prefs = await SharedPreferences.getInstance();
      ids = (prefs.getStringList(_chave) ?? []).map(int.parse).toSet();
      notifyListeners();
    }
  }

  Future<void> recarregar() async {
    if (!Sessao.instancia.logado) return;
    try {
      final lista = await Api.instancia.meusFavoritos();
      ids = lista.map((p) => p.id).toSet();
      notifyListeners();
    } catch (_) {}
  }

  bool contem(int id) => ids.contains(id);

  Future<void> alternar(int id) async {
    final novo = !ids.contains(id);
    novo ? ids.add(id) : ids.remove(id);
    notifyListeners();
    try {
      if (Sessao.instancia.logado) {
        await Api.instancia.favoritar(id, novo);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_chave, ids.map((e) => '$e').toList());
      }
    } catch (e) {
      novo ? ids.remove(id) : ids.add(id);
      notifyListeners();
      rethrow;
    }
  }
}
