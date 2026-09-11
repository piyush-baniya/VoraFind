import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../documents/document_models.dart'
    show
        DocumentAccessState,
        DocumentAccessStateConverter,
        DocumentContentStatus,
        DocumentContentStatusConverter;
import '../ocr/ocr_models.dart' show OcrStatus, OcrStatusConverter;
import '../search/search_normalizer.dart';
import 'document_content_table.dart';
import 'documents_table.dart';
import 'index_state_table.dart';
import 'media_items_table.dart';
import 'ocr_content_table.dart';
import 'saf_grants_table.dart';

part 'app_database.g.dart';

/// VoraFind's local, on-device database. Owns the durable media index and its
/// derived enrichment.
///
/// Flutter owns this database (AGENTS.md §6); the native Android layer never
/// writes SQLite tables directly. Schema v2 adds `index_state`, the per-unit
/// checkpoint table for incremental synchronization. Schema v3 adds
/// `media_items.searchable_text`, the normalized keyword-retrieval projection
/// for local metadata search (docs `search.md`). Schema v4 adds
/// `ocr_content`, the on-device OCR text enrichment for images (docs
/// `ocr.md`) and lifts the normalizer to Unicode-aware folding so that rows
/// re-backfilled at v4 match OCR text the same way. Schema v5 adds SAF
/// document tables (`saf_grants`, `documents`, `document_content`) so PDFs
/// and plain-text files are indexed separately from MediaStore media.
@DriftDatabase(
  tables: [
    MediaItems,
    IndexState,
    OcrContent,
    SafGrants,
    Documents,
    DocumentContent,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the app database at `<documents>/vorafind.sqlite` via the
  /// `drift_flutter` helper (native SQLite, sandbox-safe temp dir).
  AppDatabase.forApp() : super(driftDatabase(name: 'vorafind'));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Every future version appends upgrade steps here instead of recreating
    // the database (docs/persistence.md §Migration).
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(indexState);
      }
      if (from < 3) {
        await m.addColumn(mediaItems, mediaItems.searchableText);
        await _backfillSearchableText();
      }
      if (from < 4) {
        await m.createTable(ocrContent);
        // Re-run the backfill: schema v4 switched the normalizer to
        // Unicode-aware folding, so existing rows must be re-normalized or
        // they would stop matching (Prompt #8 §20).
        await _backfillSearchableText();
      }
      if (from < 5) {
        await m.createTable(safGrants);
        await m.createTable(documents);
        await m.createTable(documentContent);
      }
    },
  );

  /// One-time backfill of the normalized retrieval projection for rows written
  /// before schema v3.
  ///
  /// Paged by `stable_key` so memory stays bounded regardless of library size;
  /// every existing row keeps its content and merely gains its derived search
  /// text. `searchable_text` is derived data, but it is *durably* maintained
  /// from this point on by `MediaItemMapper` (never recomputed on read).
  Future<void> _backfillSearchableText() async {
    const pageSize = 500;
    String? afterKey;
    while (true) {
      final query = select(mediaItems)
        ..where((row) => row.stableKey.isBiggerThanValue(afterKey ?? ''))
        ..orderBy([(row) => OrderingTerm.asc(row.stableKey)])
        ..limit(pageSize);
      final rows = await query.get();
      if (rows.isEmpty) break;

      for (final row in rows) {
        final searchableText = SearchNormalizer.storageText([
          row.displayName,
          row.title,
          row.relativePath,
          row.bucketDisplayName,
          row.artist,
          row.album,
        ]);
        await (update(mediaItems)
              ..where((r) => r.stableKey.equals(row.stableKey)))
            .write(MediaItemsCompanion(searchableText: Value(searchableText)));
      }

      afterKey = rows.last.stableKey;
      if (rows.length < pageSize) break;
    }
  }
}
