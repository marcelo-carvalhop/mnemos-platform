import 'package:flutter/material.dart';

/// Identidade visual Mnemos.
///
/// A interface usa exclusivamente a paleta definida para a marca. Os aliases
/// antigos permanecem durante a transição para não espalhar uma migração
/// puramente nominal por todas as telas.
abstract final class AppColors {
  static const ivory = Color(0xFFF4F1E8);       // Marfim Calmo
  static const graphite = Color(0xFF1F1F1F);    // Grafite Profundo
  static const sage = Color(0xFF7A8B72);         // Sálvia Analógica
  static const petrol = Color(0xFF365462);       // Azul Petróleo
  static const terracotta = Color(0xFFB56E52);   // Terracota Contida
  static const mist = Color(0xFFD9D5CC);         // Cinza Névoa
  static const brass = Color(0xFFB8A27A);        // Latão Fosco

  // Compatibilidade com o vocabulário usado pelas telas existentes.
  static const navy = petrol;
  static const ink = graphite;
  static const muted = sage;
  static const faint = sage;
  static const hairline = mist;
  static const fill = ivory;
  static const canvas = ivory;
  static const accent = petrol;

  static const again = terracotta;
  static const againBg = mist;
  static const hard = brass;
  static const hardBg = ivory;
  static const good = sage;
  static const goodBg = mist;
  static const easy = petrol;
  static const easyBg = mist;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.petrol,
    onPrimary: AppColors.ivory,
    secondary: AppColors.sage,
    onSecondary: AppColors.graphite,
    tertiary: AppColors.brass,
    error: AppColors.terracotta,
    onError: AppColors.ivory,
    surface: AppColors.ivory,
    onSurface: AppColors.graphite,
    outline: AppColors.mist,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.ivory,
    canvasColor: AppColors.ivory,
    dividerColor: AppColors.mist,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ivory,
      foregroundColor: AppColors.graphite,
      surfaceTintColor: AppColors.ivory,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.graphite,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: .1,
      ),
      iconTheme: IconThemeData(color: AppColors.graphite),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.petrol,
        foregroundColor: AppColors.ivory,
        disabledBackgroundColor: AppColors.mist,
        disabledForegroundColor: AppColors.sage,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.petrol : null,
      ),
      checkColor: const WidgetStatePropertyAll(AppColors.ivory),
      side: const BorderSide(color: AppColors.sage),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.ivory,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.mist),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.petrol, width: 1.4),
      ),
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.graphite),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.graphite),
      bodyMedium: TextStyle(fontSize: 15, color: AppColors.graphite),
      bodySmall: TextStyle(fontSize: 12, color: AppColors.sage),
    ),
  );
}
