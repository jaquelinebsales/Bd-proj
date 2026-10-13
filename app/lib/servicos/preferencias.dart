import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Combustível e raio escolhidos pelo usuário, compartilhados entre mapa, busca e favoritos.
class Preferencias {
  Preferencias._();
  static final produto = ValueNotifier<int>(1);

  /// Distância máxima dos postos em km, contada da posição do usuário. Null: qualquer distância.
  static final raioKm = ValueNotifier<double?>(null);
  static const raios = [2.0, 5.0, 10.0, 20.0];

  static Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    produto.value = prefs.getInt('produto') ?? 1;
    final raio = prefs.getDouble('raio_km');
    raioKm.value = raios.contains(raio) ? raio : null;
    produto.addListener(() async => (await SharedPreferences.getInstance()).setInt('produto', produto.value));
    raioKm.addListener(() async {
      final p = await SharedPreferences.getInstance();
      final v = raioKm.value;
      v == null ? await p.remove('raio_km') : await p.setDouble('raio_km', v);
    });
  }
}
