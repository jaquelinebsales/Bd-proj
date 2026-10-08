import 'package:flutter/material.dart';

/// Tema Material 3 com a paleta "Asfalto": grafite azulado na marca, para que os pinos de preço sejam a única cor
/// forte sobre o mapa. Os tons principais são fixos (não dependem do algoritmo do Material) e foram medidos:
/// todo texto passa de 4,5:1 sobre o fundo em que aparece.
class Tema {
  static const marca = Color(0xFF2C3E57);

  static ThemeData claro() => _tema(Brightness.light);
  static ThemeData escuro() => _tema(Brightness.dark);

  /// Cores do preço e da ANP no tema em uso.
  static CoresPreco cores(BuildContext context) => Theme.of(context).extension<CoresPreco>() ?? CoresPreco.claro;

  static ColorScheme _esquema(Brightness b) {
    final base = ColorScheme.fromSeed(seedColor: marca, brightness: b);
    if (b == Brightness.light) {
      return base.copyWith(
        primary: marca,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFD9E2EE),
        onPrimaryContainer: const Color(0xFF142235),
        // Filtro de combustível escolhido e aba ativa usam o tom suave da marca
        secondaryContainer: const Color(0xFFD9E2EE),
        onSecondaryContainer: const Color(0xFF142235),
        surface: const Color(0xFFF6F7F9),
        surfaceDim: const Color(0xFFD7DBE1),
        surfaceBright: const Color(0xFFF6F7F9),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF1F3F6),
        surfaceContainer: const Color(0xFFECEFF3),
        surfaceContainerHigh: const Color(0xFFE6E9EE),
        surfaceContainerHighest: const Color(0xFFDFE3E9),
        onSurface: const Color(0xFF191C21),
        onSurfaceVariant: const Color(0xFF4A5361),
        outline: const Color(0xFF5F6875),
        outlineVariant: const Color(0xFFD0D6DE),
        inverseSurface: const Color(0xFF2B3038),
        onInverseSurface: const Color(0xFFEEF1F5),
        inversePrimary: const Color(0xFFA9C3E6),
      );
    }
    return base.copyWith(
      primary: const Color(0xFFA9C3E6),
      onPrimary: const Color(0xFF0E2340),
      primaryContainer: const Color(0xFF33465F),
      onPrimaryContainer: const Color(0xFFDCE6F3),
      secondaryContainer: const Color(0xFF33465F),
      onSecondaryContainer: const Color(0xFFDCE6F3),
      surface: const Color(0xFF101317),
      surfaceDim: const Color(0xFF101317),
      surfaceBright: const Color(0xFF343C47),
      surfaceContainerLowest: const Color(0xFF0B0D10),
      surfaceContainerLow: const Color(0xFF161A20),
      surfaceContainer: const Color(0xFF1E242C),
      surfaceContainerHigh: const Color(0xFF252C35),
      surfaceContainerHighest: const Color(0xFF2D3540),
      onSurface: const Color(0xFFE4E8EE),
      onSurfaceVariant: const Color(0xFFAAB3BF),
      outline: const Color(0xFF8B95A3),
      outlineVariant: const Color(0xFF3B4553),
      inverseSurface: const Color(0xFFE4E8EE),
      onInverseSurface: const Color(0xFF1E242C),
      inversePrimary: marca,
    );
  }

  static ThemeData _tema(Brightness b) {
    final esquema = _esquema(b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      visualDensity: VisualDensity.standard,
      extensions: [b == Brightness.light ? CoresPreco.claro : CoresPreco.escuro],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: esquema.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: esquema.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: esquema.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      // A barra inferior fica um degrau abaixo dos cartões, para não se misturar com a lista que rola por trás
      navigationBarTheme: NavigationBarThemeData(backgroundColor: esquema.surfaceContainerLow),
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

/// Cores do preço (semáforo da idade), da estimativa e da pesquisa ANP. No escuro, os tons são claros para texto,
/// selos e bolinhas. Os pinos preenchidos do mapa usam sempre os tons do tema claro, com o número em branco.
@immutable
class CoresPreco extends ThemeExtension<CoresPreco> {
  final Color anp;
  final Color recente; // até 24 horas
  final Color antigo; // de 2 a 7 dias
  final Color semAtualizacao; // mais de 7 dias
  final Color estimativa;
  final Color semPreco;
  final Color bordaSemPreco;
  final Color fundoPino; // pinos de contorno: preço velho, estimativa e posto sem preço

  const CoresPreco({
    required this.anp,
    required this.recente,
    required this.antigo,
    required this.semAtualizacao,
    required this.estimativa,
    required this.semPreco,
    required this.bordaSemPreco,
    required this.fundoPino,
  });

  static const claro = CoresPreco(
    anp: Color(0xFF1D4ED8),
    recente: Color(0xFF15803D),
    antigo: Color(0xFFB45309),
    semAtualizacao: Color(0xFFB91C1C),
    estimativa: Color(0xFF475569),
    semPreco: Color(0xFF6B7280),
    bordaSemPreco: Color(0xFF9CA3AF),
    fundoPino: Colors.white,
  );

  static const escuro = CoresPreco(
    anp: Color(0xFF5B9BFF),
    recente: Color(0xFF4ADE80),
    antigo: Color(0xFFFB923C),
    semAtualizacao: Color(0xFFF87171),
    estimativa: Color(0xFFC0CAD8),
    semPreco: Color(0xFF9CA3AF),
    bordaSemPreco: Color(0xFF6B7280),
    fundoPino: Color(0xFF1E242C),
  );

  @override
  CoresPreco copyWith({
    Color? anp,
    Color? recente,
    Color? antigo,
    Color? semAtualizacao,
    Color? estimativa,
    Color? semPreco,
    Color? bordaSemPreco,
    Color? fundoPino,
  }) =>
      CoresPreco(
        anp: anp ?? this.anp,
        recente: recente ?? this.recente,
        antigo: antigo ?? this.antigo,
        semAtualizacao: semAtualizacao ?? this.semAtualizacao,
        estimativa: estimativa ?? this.estimativa,
        semPreco: semPreco ?? this.semPreco,
        bordaSemPreco: bordaSemPreco ?? this.bordaSemPreco,
        fundoPino: fundoPino ?? this.fundoPino,
      );

  @override
  CoresPreco lerp(CoresPreco? other, double t) {
    if (other == null) return this;
    return CoresPreco(
      anp: Color.lerp(anp, other.anp, t)!,
      recente: Color.lerp(recente, other.recente, t)!,
      antigo: Color.lerp(antigo, other.antigo, t)!,
      semAtualizacao: Color.lerp(semAtualizacao, other.semAtualizacao, t)!,
      estimativa: Color.lerp(estimativa, other.estimativa, t)!,
      semPreco: Color.lerp(semPreco, other.semPreco, t)!,
      bordaSemPreco: Color.lerp(bordaSemPreco, other.bordaSemPreco, t)!,
      fundoPino: Color.lerp(fundoPino, other.fundoPino, t)!,
    );
  }
}
