import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Combustível escolhido pelo usuário, compartilhado entre mapa, busca e favoritos.
class Preferencias {
  Preferencias._();
  static final produto = ValueNotifier<int>(1);

  static Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    produto.value = prefs.getInt('produto') ?? 1;
    produto.addListener(() async => (await SharedPreferences.getInstance()).setInt('produto', produto.value));
  }
}
