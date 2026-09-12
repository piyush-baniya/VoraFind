import 'package:drift/drift.dart';

import '../database/app_database.dart'
    show AppDatabase, ImageVisualEmbedding, ImageVisualEmbeddingsCompanion;
import '../database/image_visual_tables.dart' show ImageVisualEmbeddings;
import '../database/media_items_table.dart' show MediaItems;
import '../platform/content_access_models.dart' show ContentCategory;
import '../semantic/vector_codec.dart' show VectorCodec;
import '../semantic/vector_math.dart' show VectorMath;
import 'image_visual_models.dart';
import 'image_visual_repository.dart';

/// Drift-backed store over `image_visual_embeddings` (schema v8).
///
/// Indexing-side retrieval is bounded and resumable: the eligibility WHERE
/// clause (missing/stale/failed-past-cooldown) mirrors the OCR, semantic, and
/// video-visual repositories so a run only touches images that genuinely need
/// work. Search-side retrieval is **bounded, filter-aware, deterministic
/// brute-force**: the SQL fetch caps the pool and applies media filters before
/// ranking; only that pool's vectors are decoded and scored in Dart
/// (docs `similar-image-search.md` §Retrieval).
class DriftImageVisualRepository
    implements ImageVisualIndexRepository, ImageVisualSearchRepository {
  DriftImageVisualRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // Indexing side
  // ---------------------------------------------------------------------------

  @override
  Future<List<ImageVisualCandidate>> findImageVisualCandidates({
    required int batchSize,
    required String modelId,
    required int nowEpochSeconds,
    int retryCooldownSeconds = ImageVisualDefaults.retryCooldownSeconds,
  }) async {
    final media = _db.mediaItems;
    final emb = _db.imageVisualEmbeddings;
    final cooldownCutoff = nowEpochSeconds - retryCooldownSeconds;

    final query =
        _db.select(media).join([
            leftOuterJoin(emb, emb.stableKey.equalsExp(media.stableKey)),
          ])
          ..where(media.category.equals(ContentCategory.images.name))
          ..where(
            _eligibility(
              emb,
              media: media,
              modelId: modelId,
              cooldownCutoff: cooldownCutoff,
            ),
          )
          ..orderBy([OrderingTerm.asc(media.stableKey)])
          ..limit(batchSize);

    final rows = await query.get();
    final result = <ImageVisualCandidate>[];
    for (final row in rows) {
      final m = row.readTable(media);
      result.add(
        ImageVisualCandidate(
          stableKey: m.stableKey,
          sourceRevision: m.metadataRevision,
          contentUri: m.contentUri,
        ),
      );
    }
    return result;
  }

  static Expression<bool> _eligibility(
    ImageVisualEmbeddings s, {
    required MediaItems media,
    required String modelId,
    required int cooldownCutoff,
  }) {
    final missingRow = s.stableKey.isNull();
    final staleCompleted =
        s.status.equals(ImageVisualStatus.completed.name) &
        s.sourceRevision.isSmallerThan(media.metadataRevision);
    final staleModel =
        s.status.equals(ImageVisualStatus.completed.name) &
        s.modelId.equals(modelId).not();
    final retryFailure =
        s.status.equals(ImageVisualStatus.failed.name) &
        s.updatedAt.isSmallerOrEqualValue(cooldownCutoff);
    return missingRow | staleCompleted | staleModel | retryFailure;
  }

  @override
  Future<void> saveEmbedding({
    required String stableKey,
    required int sourceRevision,
    required String modelId,
    required List<double> vector,
    required int nowEpochSeconds,
  }) async {
    await _db
        .into(_db.imageVisualEmbeddings)
        .insert(
          ImageVisualEmbeddingsCompanion.insert(
            stableKey: stableKey,
            sourceRevision: sourceRevision,
            modelId: modelId,
            dimensions: vector.length,
            embeddingData: Value(VectorCodec.encode(vector)),
            quantization: Value(ImageVisualDefaults.quantizationF32),
            status: ImageVisualStatus.completed.name,
            createdAt: nowEpochSeconds,
            updatedAt: nowEpochSeconds,
          ),
          onConflict: DoUpdate(
            (_) => ImageVisualEmbeddingsCompanion(
              sourceRevision: Value(sourceRevision),
              modelId: Value(modelId),
              dimensions: Value(vector.length),
              embeddingData: Value(VectorCodec.encode(vector)),
              quantization: Value(ImageVisualDefaults.quantizationF32),
              status: Value(ImageVisualStatus.completed.name),
              updatedAt: Value(nowEpochSeconds),
            ),
          ),
        );
  }

  @override
  Future<void> saveFailure({
    required String stableKey,
    required int sourceRevision,
    required String modelId,
    required String errorCode,
    required int nowEpochSeconds,
    required bool permanent,
  }) async {
    final status = permanent
        ? ImageVisualStatus.unsupported.name
        : ImageVisualStatus.failed.name;
    await _db
        .into(_db.imageVisualEmbeddings)
        .insert(
          ImageVisualEmbeddingsCompanion.insert(
            stableKey: stableKey,
            sourceRevision: sourceRevision,
            modelId: modelId,
            dimensions: 0,
            status: status,
            errorCode: Value(errorCode),
            createdAt: nowEpochSeconds,
            updatedAt: nowEpochSeconds,
          ),
          onConflict: DoUpdate(
            (_) => ImageVisualEmbeddingsCompanion(
              sourceRevision: Value(sourceRevision),
              modelId: Value(modelId),
              status: Value(status),
              errorCode: Value(errorCode),
              updatedAt: Value(nowEpochSeconds),
            ),
          ),
        );
  }

  @override
  Future<ImageVisualStats> stats() async {
    var completed = 0;
    var failed = 0;
    var unsupported = 0;
    final totalQuery = _db.selectOnly(_db.imageVisualEmbeddings)
      ..addColumns([countAll()]);
    final total = (await totalQuery.getSingle()).read(countAll()) ?? 0;
    final byStatus = _db.selectOnly(_db.imageVisualEmbeddings)
      ..addColumns([_db.imageVisualEmbeddings.status, countAll()])
      ..groupBy([_db.imageVisualEmbeddings.status]);
    for (final row in await byStatus.get()) {
      final count = row.read(countAll()) ?? 0;
      switch (row.read(_db.imageVisualEmbeddings.status)) {
        case 'completed':
          completed = count;
        case 'failed':
          failed = count;
        case 'unsupported':
          unsupported = count;
        case _:
          break;
      }
    }
    return ImageVisualStats(
      total: total,
      completed: completed,
      failed: failed,
      unsupported: unsupported,
    );
  }

  @override
  Future<ImageVisualStatus?> getStatus(String stableKey) async {
    final row = await (_db.select(
      _db.imageVisualEmbeddings,
    )..where((s) => s.stableKey.equals(stableKey))).getSingleOrNull();
    if (row == null) return null;
    return ImageVisualStatus.values.asNameMap()[row.status] ??
        ImageVisualStatus.failed;
  }

  @override
  Future<void> clear() async {
    await _db.delete(_db.imageVisualEmbeddings).go();
  }

  // ---------------------------------------------------------------------------
  // Search side (bounded, filter-aware, deterministic brute-force top-K)
  // ---------------------------------------------------------------------------

  @override
  Future<StoredImageEmbedding?> getCurrentEmbedding({
    required String stableKey,
    required String modelId,
    required int dimensions,
  }) async {
    final row =
        await (_db.select(_db.imageVisualEmbeddings)..where(
              (s) =>
                  s.stableKey.equals(stableKey) &
                  s.status.equals(ImageVisualStatus.completed.name) &
                  s.modelId.equals(modelId) &
                  s.dimensions.equals(dimensions),
            ))
            .getSingleOrNull();
    if (row == null || row.embeddingData == null) return null;
    final vector = VectorCodec.decode(row.embeddingData);
    if (vector.length != dimensions) return null;
    if (VectorMath.cosine(vector, vector) == null) return null; // non-finite.
    return StoredImageEmbedding(
      stableKey: row.stableKey,
      sourceRevision: row.sourceRevision,
      modelId: row.modelId,
      dimensions: row.dimensions,
      vector: vector,
    );
  }

  @override
  Future<List<SimilarImageMatch>> findSimilarImages({
    required List<double> referenceVector,
    required String modelId,
    required int dimensions,
    required int maxResults,
    double minSimilarity = ImageVisualDefaults.minSimilarity,
    String? excludeStableKey,
    List<String>? mediaCategories,
    bool? isScreenshot,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  }) async {
    if (referenceVector.length != dimensions) return const [];
    if (referenceVector.any((v) => v.isNaN || v.isInfinite)) return const [];
    final limit = maxResults < 1
        ? 1
        : _mathMin(
            maxResults * ImageVisualDefaults.candidatePoolMultiple,
            ImageVisualDefaults.maxCandidatePool,
          );

    final emb = _db.imageVisualEmbeddings;
    final media = _db.mediaItems;

    final query =
        _db.select(emb).join([
            innerJoin(media, media.stableKey.equalsExp(emb.stableKey)),
          ])
          ..where(
            emb.status.equals(ImageVisualStatus.completed.name) &
                emb.modelId.equals(modelId) &
                emb.dimensions.equals(dimensions) &
                _searchFilters(
                  media,
                  mediaCategories: mediaCategories,
                  isScreenshot: isScreenshot,
                  dateFrom: dateFrom,
                  dateTo: dateTo,
                  pathPrefix: pathPrefix,
                ) &
                (excludeStableKey == null
                    ? const Constant(true)
                    : emb.stableKey.isNotValue(excludeStableKey)),
          )
          ..orderBy([OrderingTerm.asc(emb.stableKey)])
          ..limit(limit);

    final rows = await query.get();
    return _scoreAndPick(
      rows.map((row) => row.readTable(emb)).toList(growable: false),
      referenceVector,
      minSimilarity,
      maxResults,
    );
  }

  Expression<bool> _searchFilters(
    MediaItems m, {
    List<String>? mediaCategories,
    bool? isScreenshot,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  }) {
    // Embeddings only exist for images, but the base check keeps retrieval
    // independent of whether the vector store ever broadens.
    Expression<bool> where = m.category.equals(ContentCategory.images.name);
    if (mediaCategories != null && mediaCategories.isNotEmpty) {
      where = where & m.category.isIn(mediaCategories);
    }
    if (isScreenshot != null) {
      where = where & m.isScreenshot.equals(isScreenshot);
    }
    if (dateFrom != null) {
      where = where & m.dateModified.isBiggerOrEqualValue(dateFrom);
    }
    if (dateTo != null) {
      where = where & m.dateModified.isSmallerOrEqualValue(dateTo);
    }
    if (pathPrefix != null && pathPrefix.isNotEmpty) {
      where = where & m.relativePath.like('$pathPrefix%');
    }
    return where;
  }

  /// Decodes each row's vector, computes cosine against [referenceVector],
  /// excludes matches below [minSimilarity], and returns the top [limit]
  /// deterministically (similarity desc → stableKey asc). Malformed rows are
  /// skipped, never thrown (AGENTS.md §19).
  List<SimilarImageMatch> _scoreAndPick(
    List<ImageVisualEmbedding> rows,
    List<double> referenceVector,
    double minSimilarity,
    int limit,
  ) {
    final scored = <SimilarImageMatch>[];
    for (final row in rows) {
      final vector = VectorCodec.decode(row.embeddingData);
      if (vector.length != row.dimensions) continue;
      final similarity = VectorMath.cosine(referenceVector, vector);
      if (similarity == null || similarity < minSimilarity) continue;
      scored.add(
        SimilarImageMatch(stableKey: row.stableKey, similarity: similarity),
      );
    }
    scored.sort((a, b) {
      final bySim = b.similarity.compareTo(a.similarity);
      if (bySim != 0) return bySim;
      return a.stableKey.compareTo(b.stableKey);
    });
    return scored.take(limit).toList(growable: false);
  }

  static int _mathMin(int a, int b) => a < b ? a : b;
}
