import 'package:flutter/material.dart';

/// Tema Material 3 com a paleta das telas de referência (verde petróleo).
class Tema {
  static const semente = Color(0xFF0F7A5C);
  static const anp = Color(0xFF2E5AAC);
  static const recente = Color(0xFF1E9E55);
  static const antigo = Color(0xFFD99A00);
  static const semAtualizacao = Color(0xFFD1453B);
  static const estimativa = Color(0xFF8A6D3B);

  static ThemeData claro() => _tema(Brightness.light);
  static ThemeData escuro() => _tema(Brightness.dark);

  static ThemeData _tema(Brightness b) {
    final esquema = ColorScheme.fromSeed(seedColor: semente, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: esquema.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: esquema.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: esquema.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
