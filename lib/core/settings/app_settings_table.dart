import 'package:drift/drift.dart';

/// Very small keyed settings store (one row: the singleton `app` key).
///
/// This is the project's own local persistence mechanism (Drift/SQLite,
/// AGENTS.md §6), so the user's appearance choice survives restarts with no
/// new dependency, no backend, and no account. The table schema v9.
class AppSettings extends Table {
  /// Singleton key; only the row with `key == 'app'` is ever read.
  TextColumn get key => text()();

  /// Wire value of the user's [AppThemePreference]; null → the dark-first
  /// default (a new user keeps VoraFind's AMOLED-oriented baseline).
  TextColumn get themeMode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
