import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/providers.dart';
import 'app_settings_repository.dart';
import 'settings_models.dart';

/// Local settings store (Drift-backed, offline-first, no account).
final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  return DriftAppSettingsRepository(ref.watch(databaseProvider));
});

/// The active appearance preference.
///
/// Starts at the dark-first default and refreshes from local storage on first
/// read, so `MaterialApp.themeMode` is always well-defined. Every change is
/// persisted locally through [appSettingsRepositoryProvider].
final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, AppThemePreference>(
      ThemePreferenceNotifier.new,
    );

class ThemePreferenceNotifier extends Notifier<AppThemePreference> {
  @override
  AppThemePreference build() {
    Future<void>.microtask(_load);
    return AppThemePreference.dark;
  }

  Future<void> _load() async {
    final stored = await ref.read(appSettingsRepositoryProvider).getTheme();
    state = stored;
  }

  void setMode(AppThemePreference mode) {
    state = mode;
    unawaited(ref.read(appSettingsRepositoryProvider).setTheme(mode));
  }
}
