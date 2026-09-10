import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography for the dark VoraFind theme.
///
/// Built on the Material 3 type ramp so text scales correctly with the
/// platform accessibility settings. Only the styles actually needed by
/// the current foundation are customized; the rest keep Material defaults.
abstract final class AppTypography {
  static TextTheme dark() {
    final base = Typography.material2021().black;
    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 34,
        height: 1.1,
        letterSpacing: -1.2,
        color: AppColors.textPrimary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: AppColors.textPrimary,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0.2,
        color: AppColors.textSecondary,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        height: 1.4,
        color: AppColors.textSecondary,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: AppColors.textPrimary,
      ),
      bodySmall: base.bodySmall?.copyWith(
        letterSpacing: 0.3,
        color: AppColors.textTertiary,
      ),
    );
  }
}
