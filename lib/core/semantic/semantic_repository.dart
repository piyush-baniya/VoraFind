import 'semantic_models.dart';

/// One source item that still needs (or may retry) a current embedding.
///
/// Carries the already-indexed, already-derived fields needed to build the
/// deterministic semantic input — never raw file bytes.
class SemanticCandidate {
  const SemanticCandidate({
    required this.stableKey,
    required this.contentType,
    required this.sourceRevision,
    required this.displayName,
    this.relativePath,
    this.text,
    this.isScreenshot,
  });

  final String stableKey;
  final SemanticContentType contentType;
  final int sourceRevision;
  final String displayName;
  final String? relativePath;

  /// Current OCR text (media) or extracted text (document); null when none.
  final String? text;

  /// Media-only screenshot flag.
  final bool? isScreenshot;
}

/// A completed, model-current embedding as stored.
class StoredEmbedding {
  const StoredEmbedding({
    required this.stableKey,
    required this.contentType,
    required this.sourceRevision,
    required this.modelId,
    required this.dimensions,
    required this.vector,
  });

  final String stableKey;
  final SemanticContentType contentType;
  final int sourceRevision;
  final String modelId;
  final int dimensions;
  final List<double> vector;
}

/// Indexing-side data access for semantic enrichment (docs
/// `semantic-search.md` §Storage). Isolates Drift behind a bounded, resumable
/// seam so the coordinator and its tests never touch SQL.
abstract interface class SemanticIndexRepository {
  /// Pages the pool of source items that need a current embedding: missing
  /// rows, completed-but-stale (revision or model changed), or `failed` past
  /// the cooldown. Bounded by [batchSize].
  Future<List<SemanticCandidate>> findEmbeddingCandidates({
    required int batchSize,
    required String modelId,
    required int dimensions,
    required int nowEpochSeconds,
    int retryCooldownSeconds = SemanticDefaults.retryCooldownSeconds,
  });

  Future<void> saveEmbedding({
    required String stableKey,
    required SemanticContentType contentType,
    required int sourceRevision,
    required String modelId,
    required List<double> vector,
    required int nowEpochSeconds,
  });

  Future<void> saveFailure({
    required String stableKey,
    required SemanticContentType contentType,
    required int sourceRevision,
    required String modelId,
    required String errorCode,
    required int nowEpochSeconds,
    required bool permanent,
  });

  Future<SemanticStats> stats();

  Future<SemanticEmbeddingStatus?> getStatus(
    String stableKey,
    SemanticContentType contentType,
  );

  Future<void> clear();
}

/// Search-side retrieval over the completed vector store.
///
/// Implementations must be **bounded and filter-aware**: they return at most
/// a capped pool sorted by similarity, and apply the caller's content-type /
/// media / document filters in SQL *before* any vector math so semantic
/// results can never cross a filter boundary (docs `semantic-search.md`
/// §Filters).
abstract interface class SemanticSearchRepository {
  Future<List<SemanticMatch>> retrieveSemanticCandidates({
    required List<double> queryVector,
    required String modelId,
    required int dimensions,
    required int maxResults,
    double minSimilarity = SemanticDefaults.minSimilarity,
    required bool includeMedia,
    required bool includeDocuments,
    Set<SemanticContentType>? contentTypes,
    List<String>? mediaCategories,
    bool? isScreenshot,
    List<String>? documentMimeTypes,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  });
}
