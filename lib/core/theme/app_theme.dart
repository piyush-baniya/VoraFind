import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the VoraFind Material theme.
///
/// VoraFind is dark-first, so the foundation ships a single dark theme
/// tuned for AMOLED screens. A light theme is deliberately not created
/// yet to avoid carrying a half-designed surface that nobody uses.
abstract final class AppTheme {
  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.seed,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: AppColors.onAccent,
          surface: AppColors.background,
          onSurface: AppColors.textPrimary,
          surfaceContainerLowest: AppColors.background,
          surfaceContainerLow: AppColors.surface,
          surfaceContainer: AppColors.surfaceElevated,
          surfaceContainerHigh: AppColors.surfaceElevated,
          surfaceContainerHighest: AppColors.surfaceElevated,
          outline: AppColors.divider,
          outlineVariant: AppColors.divider,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: AppTypography.dark(),
      dividerColor: AppColors.divider,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
    );
  }
}
