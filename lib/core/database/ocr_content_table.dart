import 'package:drift/drift.dart';

import '../ocr/ocr_models.dart' show OcrStatus, OcrStatusConverter;

/// Durable OCR/recognition content for images (schema v4, `docs/ocr.md`).
///
/// One row per successfully processed image (plus permanent/transient failure
/// records). Only normalized, **derived** text lives here — never the original
/// image bytes. The row's identity is the owning `media_items.stable_key`,
/// with an `ON DELETE CASCADE` foreign key so reconciling a deleted media row
/// cannot leave orphaned enrichment data.
///
/// Status semantics (see [OcrStatus]):
/// * Missing row → pending. `createdAt`/`updatedAt` record the first and last
///   write for retry-cooldown math.
/// * [OcrStatus.completed] rows carry `text` (raw) and `normalized_text`
///   (the search projection) plus the `source_revision` they were extracted
///   from. A `media_items.metadata_revision` bump makes them stale; search
///   ignores them and the coordinator re-runs them.
/// * [OcrStatus.failed] rows carry no text and become eligible again once
///   `updated_at <= now - cooldown`.
/// * [OcrStatus.unsupported] rows are permanent; never retried.
class OcrContent extends Table {
  /// `media_items.stable_key` this enrichment belongs to.
  TextColumn get mediaStableKey => text()();

  /// Raw recognized text; null for failed/unsupported rows.
  ///
  /// Named `rawText` (SQL `raw_text`), not `text`, because drift_dev resolves a
  /// column getter named `text` against its own `text()` builder and crashes
  /// while analyzing the table.
  TextColumn get rawText => text().nullable()();

  /// Normalized search projection (`SearchNormalizer.canonical`) — the column
  /// `searchOcrCandidates` substring-matches. Null for failed/unsupported.
  TextColumn get normalizedText => text().nullable()();

  /// Durable status (see [OcrStatus]).
  TextColumn get status => text().map(const OcrStatusConverter())();

  /// `media_items.metadata_revision` this recognition was produced from.
  IntColumn get sourceRevision => integer()();

  /// Epoch seconds of the first write.
  IntColumn get createdAt => integer()();

  /// Epoch seconds of the most recent write (drives retry cooldowns).
  IntColumn get updatedAt => integer()();

  /// Stable failure code (`OcrErrorCode.name`); null when not an error.
  TextColumn get errorCode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {mediaStableKey};

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY (media_stable_key) '
        'REFERENCES media_items (stable_key) ON DELETE CASCADE',
  ];
}
