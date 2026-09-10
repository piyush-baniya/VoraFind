import 'package:flutter/material.dart';

/// VoraFind design tokens.
///
/// The palette is dark-first and AMOLED-friendly: surfaces are near pure
/// black and elevation is communicated with small gray steps rather than
/// heavy shadows. The violet accent is used sparingly for the brand mark,
/// primary actions, and selection states.
abstract final class AppColors {
  /// Seed color for generating the Material tonal palette.
  static const Color seed = Color(0xFF7D6BF0);

  /// Primary accent used carefully across the interface.
  static const Color accent = Color(0xFF8B7BF7);

  /// Content drawn on top of the accent color (high-contrast dark).
  static const Color onAccent = Color(0xFF0B0B10);

  /// Subtle tint behind accent icons/brand elements.
  static const Color accentSubtle = Color(0x178B7BF7);

  /// Hairline ring used around brand/accent elements.
  static const Color accentRing = Color(0x338B7BF7);

  /// Near-black application background (AMOLED-friendly).
  static const Color background = Color(0xFF000000);

  /// Slightly raised surface for cards and chips.
  static const Color surface = Color(0xFF0D0D10);

  /// Further raised surfaces (dialogs, popovers, etc.).
  static const Color surfaceElevated = Color(0xFF16161A);

  /// Borders and dividers.
  static const Color divider = Color(0xFF1E1E23);

  /// Primary text on dark surfaces.
  static const Color textPrimary = Color(0xFFF2F2F4);

  /// Secondary text.
  static const Color textSecondary = Color(0xFF9C9CA5);

  /// Tertiary text and captions.
  static const Color textTertiary = Color(0xFF6C6C74);
}
