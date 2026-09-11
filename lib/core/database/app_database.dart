import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'index_state_table.dart';
import 'media_items_table.dart';

part 'app_database.g.dart';

/// VoraFind's local, on-device database. Owns the durable media index.
///
/// Flutter owns this database (AGENTS.md §6); the native Android layer never
/// writes SQLite tables directly. Schema v2 adds `index_state`, the per-unit
/// checkpoint table for incremental synchronization. Future tables
/// (`ocr_content`, `text_index`, `image_features`, `video_segments`,
/// `audio_transcripts`, …) are deliberately deferred (see
/// `docs/persistence.md`).
@DriftDatabase(tables: [MediaItems, IndexState])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the app database at `<documents>/vorafind.sqlite` via the
  /// `drift_flutter` helper (native SQLite, sandbox-safe temp dir).
  AppDatabase.forApp() : super(driftDatabase(name: 'vorafind'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Every future version appends upgrade steps here instead of recreating
    // the database (docs/persistence.md §Migration).
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(indexState);
      }
    },
  );
}
