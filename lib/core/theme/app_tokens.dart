import 'package:flutter/material.dart';

/// Centralized spacing scale for the whole application (design system §66).
///
/// Prefer these tokens over hard-coded padding/margins so both themes and all
/// screens stay visually consistent.
abstract final class VoraSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xl2 = 32;
  static const double xl3 = 40;
}

/// Centralized corner radii (design system §66).
abstract final class VoraRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 999;
}

/// Centralized durations. Micro-interactions live in 150–300ms (Prompt #16.5
/// §15); anything longer must earn it.
abstract final class VoraDuration {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
}

/// Centralized icon sizes (design system §66).
abstract final class VoraIconSize {
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 28;
}

/// Returns true when the platform requests reduced motion. Use it to disable
/// non-essential animation (Prompt #16.5 §55).
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
