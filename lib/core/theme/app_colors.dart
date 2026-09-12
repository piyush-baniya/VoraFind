import 'package:flutter/material.dart';

/// VoraFind design tokens.
///
/// The dark palette is dark-first and AMOLED-friendly: surfaces are near pure
/// black and elevation is communicated with small gray steps rather than heavy
/// shadows. The violet accent is used sparingly for the brand mark, primary
/// actions, and selection states (never the whole background). The light
/// palette is a genuinely separate design, not an inverted dark theme (Prompt
/// #16.5 §4): cool white surfaces on a soft neutral scaffold with a deeper
/// accent that keeps text contrast accessible.
abstract final class AppColors {
  /// Seed color for generating the Material tonal palette.
  static const Color seed = Color(0xFF7D6BF0);

  /// Dark palette (mirrored by [VoraColors.dark]).
  static const Color accent = Color(0xFF8B7BF7);
  static const Color onAccent = Color(0xFF0B0B10);
  static const Color accentSubtle = Color(0x178B7BF7);
  static const Color accentRing = Color(0x338B7BF7);
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0D0D10);
  static const Color surfaceElevated = Color(0xFF16161A);
  static const Color divider = Color(0xFF1E1E23);
  static const Color textPrimary = Color(0xFFF2F2F4);
  static const Color textSecondary = Color(0xFF9C9CA5);
  static const Color textTertiary = Color(0xFF6C6C74);

  /// Semantic status colors (dark).
  static const Color success = Color(0xFF4CC38A);
  static const Color warning = Color(0xFFF5B04C);
  static const Color danger = Color(0xFFF2555A);
}

/// Light palette (mirrored by [VoraColors.light]).
abstract final class AppColorsLight {
  static const Color accent = Color(0xFF6C5CE7);
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color accentSubtle = Color(0x126C5CE7);
  static const Color accentRing = Color(0x246C5CE7);
  static const Color background = Color(0xFFF7F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE7E7EC);
  static const Color textPrimary = Color(0xFF191920);
  static const Color textSecondary = Color(0xFF5B5B66);
  static const Color textTertiary = Color(0xFF8E8E99);

  static const Color success = Color(0xFF23834F);
  static const Color warning = Color(0xFF9A6700);
  static const Color danger = Color(0xFFC62B32);
}

/// Semantic color set exposed through the theme so both themes share one UI
/// vocabulary. Widgets read `context.voraColors` instead of hard-coding
/// palette values (Prompt #16.5 §66).
class VoraColors extends ThemeExtension<VoraColors> {
  const VoraColors({
    required this.accent,
    required this.onAccent,
    required this.accentSubtle,
    required this.accentRing,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const VoraColors dark = VoraColors(
    accent: AppColors.accent,
    onAccent: AppColors.onAccent,
    accentSubtle: AppColors.accentSubtle,
    accentRing: AppColors.accentRing,
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceElevated: AppColors.surfaceElevated,
    divider: AppColors.divider,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
  );

  static const VoraColors light = VoraColors(
    accent: AppColorsLight.accent,
    onAccent: AppColorsLight.onAccent,
    accentSubtle: AppColorsLight.accentSubtle,
    accentRing: AppColorsLight.accentRing,
    background: AppColorsLight.background,
    surface: AppColorsLight.surface,
    surfaceElevated: AppColorsLight.surfaceElevated,
    divider: AppColorsLight.divider,
    textPrimary: AppColorsLight.textPrimary,
    textSecondary: AppColorsLight.textSecondary,
    textTertiary: AppColorsLight.textTertiary,
    success: AppColorsLight.success,
    warning: AppColorsLight.warning,
    danger: AppColorsLight.danger,
  );

  final Color accent;
  final Color onAccent;
  final Color accentSubtle;
  final Color accentRing;
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color success;
  final Color warning;
  final Color danger;

  @override
  VoraColors copyWith({
    Color? accent,
    Color? onAccent,
    Color? accentSubtle,
    Color? accentRing,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return VoraColors(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      accentRing: accentRing ?? this.accentRing,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  VoraColors lerp(ThemeExtension<VoraColors>? other, double t) {
    if (other is! VoraColors) return this;
    return VoraColors(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      accentRing: Color.lerp(accentRing, other.accentRing, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Theme-aware access to VoraFind's semantic colors.
extension VoraThemeContext on BuildContext {
  VoraColors get vora => Theme.of(this).extension<VoraColors>()!;
}
