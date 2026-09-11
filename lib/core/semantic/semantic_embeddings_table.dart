import 'package:drift/drift.dart';

import 'semantic_models.dart' show SemanticContentTypeConverter;

/// Local semantic/embedding vector store (schema v6, `docs/semantic-search.md`).
///
/// One row per embedded source item (media row or SAF document), keyed by the
/// source's stable identity plus its [SemanticContentType]. Never stores
/// original file bytes — only the derived fixed-dimensional vector.
///
/// Polymorphism note: the same [stableKey] space is shared by
/// `media_items.stable_key` and `documents.stable_key`, which a single SQLite
/// foreign key cannot express. Source integrity (cascade delete on source
/// removal) is therefore enforced at the application layer and documented in
/// `docs/semantic-search.md` §Storage.
@TableIndex(name: 'idx_semantic_status_key', columns: {#status, #stableKey})
class SemanticEmbeddings extends Table {
  /// Stable identity of the source item (`media_items` or `documents`).
  TextColumn get stableKey => text()();

  /// Which source surface the vector belongs to ([SemanticContentType.name]).
  TextColumn get contentType =>
      text().map(const SemanticContentTypeConverter())();

  /// `metadata_revision` (media) or `source_revision` (document) this vector
  /// was produced from. A source revision bump makes the vector stale.
  IntColumn get sourceRevision => integer()();

  /// The embedding configuration this vector was produced with
  /// (`EmbeddingProvider.modelId`). A model change invalidates the vector.
  TextColumn get modelId => text()();

  /// Vector dimensionality (the provider's `dimensions`).
  IntColumn get dimensions => integer()();

  /// Serially encoded vector bytes (little-endian Float32 when
  /// [quantization] is [SemanticDefaults.quantizationF32]); null while not
  /// completed. Never more than ~384×4 bytes + overhead.
  BlobColumn get embeddingData => blob().nullable()();

  /// Encoding tag for [embeddingData] ([SemanticDefaults.quantizationF32]).
  TextColumn get quantization => text().nullable()();

  /// Durable embedding status ([SemanticEmbeddingStatus.name]).
  TextColumn get status => text()();

  /// Stable failure code (`EmbeddingErrorCode.name`); null when not an error.
  TextColumn get errorCode => text().nullable()();

  /// Epoch seconds of the first write.
  IntColumn get createdAt => integer()();

  /// Epoch seconds of the most recent write (drives retry cooldowns).
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {stableKey, contentType};
}
