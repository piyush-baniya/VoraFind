import 'package:flutter/material.dart';

import 'app_colors.dart';

/// VoraFind typography. Both themes share the same type ramp — text color is
/// the only difference — so weights, sizes, and heights stay identical across
/// light and dark (Prompt #16.5 §66).
abstract final class AppTypography {
  static TextTheme dark() => _build(
    AppColors.textPrimary,
    AppColors.textSecondary,
    AppColors.textTertiary,
  );

  static TextTheme light() => _build(
    AppColorsLight.textPrimary,
    AppColorsLight.textSecondary,
    AppColorsLight.textTertiary,
  );

  static TextTheme _build(Color primary, Color secondary, Color tertiary) {
    final base = Typography.material2021().black;
    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 34,
        height: 1.1,
        letterSpacing: -1.2,
        color: primary,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 26,
        height: 1.2,
        letterSpacing: -0.5,
        color: primary,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 20,
        height: 1.3,
        color: primary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: primary,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0.2,
        color: secondary,
      ),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.4, color: secondary),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: primary,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: secondary,
      ),
      bodySmall: base.bodySmall?.copyWith(letterSpacing: 0.3, color: tertiary),
    );
  }
}
