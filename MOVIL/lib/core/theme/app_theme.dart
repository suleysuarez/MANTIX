import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

/// Tema claro de la app. Objetivos táctiles de al menos 48 px y contraste AA:
/// el texto sobre `navy` y `steel` es blanco; sobre `sky` es `navy`.
///
/// La tipografía es la del sistema hasta tener los `.ttf` de Plus Jakarta Sans
/// (la web los carga desde Google Fonts en woff2, que Flutter no admite).
abstract final class AppTheme {
  static const double minTouchTarget = 48;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.steel,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.steel,
      onPrimary: AppColors.white,
      secondary: AppColors.mustard,
      onSecondary: AppColors.navy,
      surface: AppColors.white,
      onSurface: AppColors.navy,
      error: AppColors.error,
      onError: AppColors.white,
    );
    const minSize = Size(minTouchTarget, minTouchTarget);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.white,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minSize,
          backgroundColor: AppColors.steel,
          foregroundColor: AppColors.white,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minSize,
          foregroundColor: AppColors.steel,
          side: const BorderSide(color: AppColors.slate),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: minSize,
          foregroundColor: AppColors.steel,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        border: OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: BorderSide(color: AppColors.grey)),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: BorderSide(color: AppColors.grey)),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: BorderSide(color: AppColors.steel, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: BorderSide(color: AppColors.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: BorderSide(color: AppColors.error, width: 2)),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: AppColors.grey),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: TextStyle(color: AppColors.white),
      ),
    );
  }

  /// Dark glass theme for Mantix's native mobile authentication screens.
  static ThemeData authGlass(ThemeData base) {
    final fieldBorder = OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(
        color: AuthTokens.glassBorder.withValues(alpha: 0.55),
        width: 1,
      ),
    );
    return base.copyWith(
      cardColor: Colors.transparent,
      canvasColor: Colors.transparent,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: AuthTokens.accent,
        surface: Colors.transparent,
        onSurface: AuthTokens.textPrimary,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AuthTokens.textPrimary,
        displayColor: AuthTokens.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.10),
        hintStyle: const TextStyle(color: AuthTokens.textMuted),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AuthTokens.accent, width: 1.5),
        ),
      ),
    );
  }
}
