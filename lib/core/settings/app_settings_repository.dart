import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'settings_models.dart';

/// Local persistence boundary for user-facing app settings.
///
/// The UI depends on this interface — never on Drift rows. Reads fall back to
/// the dark-first default when no row exists yet, so first launch is always
/// coherent without a migration dance.
abstract interface class AppSettingsRepository {
  /// The persisted appearance preference (dark when never set).
  Future<AppThemePreference> getTheme();

  /// Persists the appearance preference locally.
  Future<void> setTheme(AppThemePreference value);
}

/// [AppSettingsRepository] backed by the singleton `app_settings` row.
class DriftAppSettingsRepository implements AppSettingsRepository {
  DriftAppSettingsRepository(this._db);

  final AppDatabase _db;

  static const _appKey = 'app';

  @override
  Future<AppThemePreference> getTheme() async {
    final query = _db.select(_db.appSettings)
      ..where((row) => row.key.equals(_appKey));
    final row = await query.getSingleOrNull();
    return AppThemePreference.fromWire(row?.themeMode);
  }

  @override
  Future<void> setTheme(AppThemePreference value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _appKey,
            themeMode: Value(value.wire),
          ),
        );
  }
}
