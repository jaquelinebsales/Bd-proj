import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Combustível e raio escolhidos pelo usuário, compartilhados entre mapa, busca e favoritos.
class Preferencias {
  Preferencias._();
  static final produto = ValueNotifier<Set<int>>({1});

  /// Produto principal (primeiro selecionado). Usado para exibição de preço e ordenação.
  static int get primario => produto.value.isEmpty ? 1 : produto.value.first;

  /// Distância máxima dos postos em km, contada da posição do usuário. Null: qualquer distância.
  static final raioKm = ValueNotifier<double?>(null);
  static const raios = [2.0, 5.0, 10.0, 20.0];

  static Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('produtos');
    if (saved != null && saved.isNotEmpty) {
      final ids = saved.split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toSet();
      if (ids.isNotEmpty) produto.value = ids;
    } else {
      produto.value = {prefs.getInt('produto') ?? 1};
    }
    final raio = prefs.getDouble('raio_km');
    raioKm.value = raios.contains(raio) ? raio : null;
    produto.addListener(() async => (await SharedPreferences.getInstance()).setString('produtos', produto.value.join(',')));
    raioKm.addListener(() async {
      final p = await SharedPreferences.getInstance();
      final v = raioKm.value;
      v == null ? await p.remove('raio_km') : await p.setDouble('raio_km', v);
    });
  }
}
