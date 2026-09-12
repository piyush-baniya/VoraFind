import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Builds the VoraFind Material theme for either brightness.
///
/// Dark-first, AMOLED-friendly baseline plus a genuinely light theme. Both
/// share the same component vocabulary (radii, type ramp, interaction
/// durations) and expose the semantic [VoraColors] extension that every widget
/// reads — never raw palette values outside this file (Prompt #16.5 §66).
abstract final class AppTheme {
  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    colors: VoraColors.dark,
    palette: AppColors.seed,
    onAccent: AppColors.onAccent,
    typography: AppTypography.dark(),
    systemOverlay: SystemUiOverlayStyle.light,
  );

  static ThemeData light() => _build(
    brightness: Brightness.light,
    colors: VoraColors.light,
    palette: AppColors.seed,
    onAccent: AppColorsLight.onAccent,
    typography: AppTypography.light(),
    systemOverlay: SystemUiOverlayStyle.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required VoraColors colors,
    required Color palette,
    required Color onAccent,
    required TextTheme typography,
    required SystemUiOverlayStyle systemOverlay,
  }) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: palette,
          brightness: brightness,
        ).copyWith(
          primary: colors.accent,
          onPrimary: onAccent,
          onPrimaryContainer: colors.accent,
          surface: colors.background,
          onSurface: colors.textPrimary,
          onSurfaceVariant: colors.textSecondary,
          surfaceContainerLowest: colors.background,
          surfaceContainerLow: colors.surface,
          surfaceContainer: colors.surfaceElevated,
          surfaceContainerHigh: colors.surfaceElevated,
          surfaceContainerHighest: colors.surfaceElevated,
          outline: colors.divider,
          outlineVariant: colors.divider,
          error: colors.danger,
          onError: colors.onAccent,
        );

    // Shared interaction shape: soft 12–16px radii, hash-free surfaces that
    // only lighten (never shadow), and a thin, quiet divider.
    const inputDecoration = InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(VoraRadius.md)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(VoraRadius.md)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(VoraRadius.md)),
        borderSide: BorderSide.none,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: VoraSpace.lg,
        vertical: VoraSpace.md,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      textTheme: typography,
      dividerColor: colors.divider,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: systemOverlay,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.background,
        indicatorColor: colors.accentSubtle,
        surfaceTintColor: Colors.transparent,
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(
          typography.labelMedium?.copyWith(color: colors.textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.accent
                : colors.textSecondary,
            size: VoraIconSize.lg,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: inputDecoration,
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceElevated,
        selectedColor: colors.accentSubtle,
        labelStyle: typography.labelMedium?.copyWith(color: colors.textPrimary),
        secondaryLabelStyle: typography.labelMedium?.copyWith(
          color: colors.accent,
        ),
        side: BorderSide(color: colors.divider, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VoraRadius.full),
        ),
        showCheckmark: false,
      ),
      dividerTheme: DividerThemeData(color: colors.divider, thickness: 1),
      listTileTheme: ListTileThemeData(
        textColor: colors.textPrimary,
        subtitleTextStyle: typography.bodySmall,
        iconColor: colors.textSecondary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceElevated,
        contentTextStyle: typography.bodyMedium?.copyWith(
          color: colors.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VoraRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VoraRadius.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(VoraRadius.xl),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.accentRing,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : colors.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accentRing
              : colors.surfaceElevated,
        ),
      ),
      extensions: [colors],
    );
  }
}
