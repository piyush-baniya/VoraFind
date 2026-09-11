import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'media_items_table.dart';

part 'app_database.g.dart';

/// VoraFind's local, on-device database. Owns the durable media index.
///
/// Flutter owns this database (AGENTS.md §6); the native Android layer never
/// writes SQLite tables directly. Only `media_items` exists in schema v1 —
/// future tables (`ocr_content`, `text_index`, `image_features`,
/// `video_segments`, `audio_transcripts`, `index_state`, …) are deliberately
/// deferred (see `docs/persistence.md`).
@DriftDatabase(tables: [MediaItems])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the app database at `<documents>/vorafind.sqlite` via the
  /// `drift_flutter` helper (native SQLite, sandbox-safe temp dir).
  AppDatabase.forApp() : super(driftDatabase(name: 'vorafind'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // v1 is the initial schema; every future version appends upgrade steps
    // here instead of recreating the database (docs/persistence.md §Migration).
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // No upgrades yet — schema v1 is the first release.
    },
  );
}
