import 'visual_models.dart';

/// One video that needs (or may retry) a current visual analysis, plus the row
/// coordinates needed to sample it and update the media index.
class VisualCandidate {
  const VisualCandidate({
    required this.stableKey,
    required this.sourceRevision,
    required this.contentUri,
    required this.durationMs,
    required this.displayName,
  });

  final String stableKey;
  final int sourceRevision;
  final String contentUri;

  /// MediaStore duration, when known (drives the frame-sampling schedule).
  final int? durationMs;
  final String displayName;
}

/// A stored best-match for one video against one queried concept: the concept,
/// its confidence, and the frame slot/timestamp where it appeared.
class VisualRetrievalMatch {
  const VisualRetrievalMatch({
    required this.stableKey,
    required this.concept,
    required this.confidence,
    required this.frameTsMs,
  });

  final String stableKey;
  final String concept;

  /// Aggregated label confidence (max over the video's matched frames).
  final double confidence;

  /// Timestamp (ms) of the highest-confidence matching frame.
  final int frameTsMs;
}

/// Indexing-side data access for video visual enrichment (docs
/// `video-visual-search.md` §Storage). Isolates Drift behind a bounded,
/// resumable seam so the coordinator and its tests never touch SQL.
abstract interface class VisualIndexRepository {
  /// Pages the pool of videos that need a current analysis: missing status
  /// rows, completed-but-stale (revision or model changed), or `failed` past
  /// the cooldown. Bounded by [batchSize].
  Future<List<VisualCandidate>> findVisualCandidates({
    required int batchSize,
    required String modelId,
    required int nowEpochSeconds,
    int retryCooldownSeconds = VisualDefaults.retryCooldownSeconds,
  });

  /// Persists one video's analysis: the completed status plus all frame rows.
  /// Replacing stale rows and adding/removing frames is done transactionally.
  Future<void> saveAnalysis({
    required String stableKey,
    required int sourceRevision,
    required String modelId,
    required List<AnalyzedVisualFrame> frames,
    required int nowEpochSeconds,
  });

  /// Persists a durable failed/unsupported status for one video.
  Future<void> saveFailure({
    required String stableKey,
    required int sourceRevision,
    required String modelId,
    required String errorCode,
    required int nowEpochSeconds,
    required bool permanent,
  });

  Future<VisualStats> stats();

  Future<VisualVideoStatus?> getStatus(String stableKey);

  Future<void> clear();
}

/// One analyzed frame ready to persist (concept rows derived from its
/// classification).
class AnalyzedVisualFrame {
  const AnalyzedVisualFrame({
    required this.frameIndex,
    required this.frameTsMs,
    required this.concepts,
  });

  final int frameIndex;
  final int frameTsMs;
  final List<VisualFrameConcept> concepts;
}

/// Search-side retrieval over the completed frame store.
///
/// Implementations must be **bounded and filter-aware**: they return at most a
/// capped pool caused by matching confidence, and apply the caller's media /
/// duration / date filters in SQL before ranking so visual results can never
/// cross a filter boundary.
abstract interface class VisualSearchRepository {
  /// Finds videos whose stored frames contain at least one of [concepts],
  /// returning at most [maxResults] best matches (highest confidence first,
  /// one row per video concept pair).
  Future<List<VisualRetrievalMatch>> retrieveVisualCandidates({
    required List<String> concepts,
    required int maxResults,
    List<String>? mediaCategories,
    int? dateFrom,
    int? dateTo,
    int? minDurationMs,
    int? maxDurationMs,
    double minConfidence = VisualDefaults.minConceptConfidence,
  });
}
