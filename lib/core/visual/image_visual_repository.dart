import 'image_visual_models.dart';

/// Indexing-side data access for image feature enrichment (docs
/// `similar-image-search.md` §Storage). Isolates Drift behind a bounded,
/// resumable seam so the coordinator and its tests never touch SQL.
abstract interface class ImageVisualIndexRepository {
  /// Pages the pool of images that need a current embedding: missing status
  /// rows, completed-but-stale (revision or model changed), or `failed` past
  /// the cooldown. Bounded by [batchSize].
  Future<List<ImageVisualCandidate>> findImageVisualCandidates({
    required int batchSize,
    required String modelId,
    required int nowEpochSeconds,
    int retryCooldownSeconds = ImageVisualDefaults.retryCooldownSeconds,
  });

  /// Persists one completed image embedding (replacing any prior row).
  Future<void> saveEmbedding({
    required String stableKey,
    required int sourceRevision,
    required String modelId,
    required List<double> vector,
    required int nowEpochSeconds,
  });

  /// Persists a durable failed/unsupported status for one image.
  Future<void> saveFailure({
    required String stableKey,
    required int sourceRevision,
    required String modelId,
    required String errorCode,
    required int nowEpochSeconds,
    required bool permanent,
  });

  Future<ImageVisualStats> stats();

  Future<ImageVisualStatus?> getStatus(String stableKey);

  Future<void> clear();
}

/// Search-side retrieval over the completed image vector store.
///
/// Implementations must be **bounded and filter-aware**: they return at most a
/// capped pool, fetched with the caller's media filters applied in SQL before
/// ranking, and ranking is deterministic (similarity desc → stableKey asc).
abstract interface class ImageVisualSearchRepository {
  /// The stored, current-model embedding of one image, or null when it has no
  /// usable embedding (missing, stale model, failed, or malformed row).
  Future<StoredImageEmbedding?> getCurrentEmbedding({
    required String stableKey,
    required String modelId,
    required int dimensions,
  });

  /// Finds images similar to [referenceVector], returning at most
  /// [maxResults] matched [SimilarImageMatch]es (highest cosine first,
  /// deterministic tie-break by stableKey asc). [excludeStableKey] removes one
  /// specific row (the reference image itself in Flow A).
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
  });
}
