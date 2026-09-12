import 'package:flutter/material.dart';

/// User-selected appearance mode, persisted locally (no account, no sync).
enum AppThemePreference {
  system('system'),
  light('light'),
  dark('dark');

  const AppThemePreference(this.wire);

  /// Stable wire value stored in the local `app_settings` table.
  final String wire;

  ThemeMode get themeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  String get label => switch (this) {
    AppThemePreference.system => 'System default',
    AppThemePreference.light => 'Light',
    AppThemePreference.dark => 'Dark',
  };

  static AppThemePreference fromWire(String? value) =>
      values.asNameMap()[value] ?? AppThemePreference.dark;
}
