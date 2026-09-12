import 'package:drift/drift.dart';

/// Durable image-feature vector store (schema v8, `docs/similar-image-search.md`).
///
/// One row per indexed image, keyed by the media row's stable identity. Never
/// stores original file bytes — only the derived bounded feature vector. A
/// missing row means "not yet embedded". `completed` rows carry the source
/// revision and model they were produced from — a revision or model change
/// makes them stale. `failed` rows retry after the cooldown; `unsupported`
/// rows are terminal (invalid input, zero/out-of-shape vector).
///
/// Source integrity (cascade delete on media removal) is enforced at the
/// application layer by `MediaRepository` (same design as `semantic_embeddings`
/// and `video_visual_status`).
@TableIndex(name: 'idx_image_visual_status_key', columns: {#status, #stableKey})
class ImageVisualEmbeddings extends Table {
  /// Stable identity of the source media row (`media_items.stable_key`).
  TextColumn get stableKey => text()();

  /// `media_items.metadata_revision` at embedding time. A revision bump makes
  /// the vector stale.
  IntColumn get sourceRevision => integer()();

  /// The image-feature model that produced the vector
  /// (`ImageVisualDefaults.modelId`). A model change invalidates all rows.
  TextColumn get modelId => text()();

  /// Vector dimensionality (the provider's `dimensions`).
  IntColumn get dimensions => integer()();

  /// Serially encoded vector bytes (little-endian Float32 when [quantization]
  /// is [ImageVisualDefaults.quantizationF32]); null while not completed.
  BlobColumn get embeddingData => blob().nullable()();

  /// Encoding tag for [embeddingData] ([ImageVisualDefaults.quantizationF32]).
  TextColumn get quantization => text().nullable()();

  /// Durable embedding status ([ImageVisualStatus.name]).
  TextColumn get status => text()();

  /// Stable failure code (`ImageVisualErrorCode.name`); null when not an error.
  TextColumn get errorCode => text().nullable()();

  /// Epoch seconds of the first write.
  IntColumn get createdAt => integer()();

  /// Epoch seconds of the most recent write (drives retry cooldowns).
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {stableKey};
}
