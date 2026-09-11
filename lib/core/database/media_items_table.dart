import 'package:drift/drift.dart';

/// Extraction state of a media item for the future OCR/transcription pipeline.
///
/// This is the MVP version of the architecture's `extractionState` tristate:
/// the value is durable, is reset by the extraction pipeline, and is never
/// derived from anything else in this table. `none` is the initial state;
/// `pending` and `done` are managed by a later prompt.
enum IndexingStatus { none, pending, done }

/// Durable metadata index for discovered media (architecture §15.1
/// `indexed_items`). One row per stable identity (`volumeName:mediaStoreId`).
///
/// Only MediaStore metadata is stored — never file bytes. Discovery values are
/// persisted unchanged; the database layer does not reshape them.
/// Indexing-state columns are the only durable bookkeeping kept here:
/// first/last seen timestamps, last indexed generation, a monotonic metadata
/// revision, extraction status, and the access scope the record was last seen
/// under (partial-access correctness depends on it — see `docs/persistence.md`).
///
/// Non-primary indexes are declared as [TableIndex] annotations below; each
/// exists because a concrete current or imminent query needs it:
///
/// * `(category, dateModified)` — type-filtered, recency-ordered results.
/// * `(volumeName, mediaStoreId)` — the natural MediaStore coordinates, used
///   by future generation/delta sweeps.
/// * `mimeType` — cheap type filtering in search.
/// * `relativePath` — folder browsing and screenshot-path heuristics.
/// * `(isScreenshot, category)` — screenshot-first views (architecture §15.2).
/// * `lastDiscoveredAt` — future deletion-reconciliation scans that process
///   oldest-seen rows first.
@TableIndex(
  name: 'idx_media_category_date_modified',
  columns: {#category, #dateModified},
)
@TableIndex(
  name: 'idx_media_volume_media_store_id',
  columns: {#volumeName, #mediaStoreId},
)
@TableIndex(name: 'idx_media_mime_type', columns: {#mimeType})
@TableIndex(name: 'idx_media_relative_path', columns: {#relativePath})
@TableIndex(
  name: 'idx_media_screenshot_category',
  columns: {#isScreenshot, #category},
)
@TableIndex(name: 'idx_media_last_discovered_at', columns: {#lastDiscoveredAt})
class MediaItems extends Table {
  /// Primary identity (`volumeName:mediaStoreId`), unchanged from discovery.
  TextColumn get stableKey => text()();

  /// Media content category (`ContentCategory.name` wire value).
  TextColumn get category => text()();

  TextColumn get volumeName => text()();

  /// MediaStore `_ID` within [volumeName]'s collection.
  IntColumn get mediaStoreId => integer()();

  TextColumn get contentUri => text()();

  TextColumn get displayName => text()();

  TextColumn get title => text().nullable()();

  TextColumn get mimeType => text().nullable()();

  IntColumn get sizeBytes => integer().nullable()();

  IntColumn get dateAdded => integer().nullable()();

  IntColumn get dateModified => integer().nullable()();

  TextColumn get relativePath => text().nullable()();

  TextColumn get bucketDisplayName => text().nullable()();

  IntColumn get width => integer().nullable()();

  IntColumn get height => integer().nullable()();

  IntColumn get durationMs => integer().nullable()();

  TextColumn get artist => text().nullable()();

  TextColumn get album => text().nullable()();

  /// Not yet produced by the scanner; present for the extended audio metadata
  /// that later scans will provide.
  TextColumn get albumArtist => text().nullable()();

  /// Not yet produced by the scanner; present for the extended audio metadata
  /// that later scans will provide.
  IntColumn get trackNumber => integer().nullable()();

  /// Not yet produced by the scanner; present for the extended audio metadata
  /// that later scans will provide.
  IntColumn get discNumber => integer().nullable()();

  /// Not yet produced by the scanner; present for the extended audio metadata
  /// that later scans will provide.
  TextColumn get genre => text().nullable()();

  IntColumn get screenshotScore => integer().nullable()();

  BoolColumn get isScreenshot => boolean().nullable()();

  /// Relink signature computed by the scanner. Stored verbatim — the database
  /// layer never recomputes it.
  TextColumn get relinkSignature => text().nullable()();

  /// Epoch seconds when this stable identity was first seen.
  IntColumn get firstDiscoveredAt => integer()();

  /// Epoch seconds of the most recent upsert.
  IntColumn get lastDiscoveredAt => integer()();

  /// MediaStore generation reported on the discovery batch that last carried
  /// this record (API 30+; null below). Metadata only — no delta logic yet.
  IntColumn get lastIndexedGeneration => integer().nullable()();

  /// Monotonic counter, incremented once per upsert. Distinguishes "re-seen
  /// unchanged" from "metadata changed" without storing a content hash.
  IntColumn get metadataRevision => integer()();

  /// Durable extraction state (see [IndexingStatus]); managed by later
  /// extraction prompts, preserved across metadata updates.
  TextColumn get indexingStatus => textEnum<IndexingStatus>()();

  /// Access scope (`DiscoveryAccessScope.name`: `full`/`partial`) under which
  /// this record was last seen. A partial-access re-scan that no longer
  /// returns a row must NOT be treated as deletion — this column is what lets
  /// a future reconciler make that distinction.
  TextColumn get lastSeenAccessScope => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {stableKey};
}
