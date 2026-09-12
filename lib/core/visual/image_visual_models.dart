/// Bounds and policy constants for the local image-to-image similarity
/// subsystem (`docs/similar-image-search.md`). Every value exists to keep
/// embedding generation and retrieval bounded on real phones.
abstract final class ImageVisualDefaults {
  /// Stable identity of the bundled image-feature model. Changing it
  /// invalidates every stored image row and re-embeds all images on the next
  /// run — the single invalidation lever (mirrors
  /// [VisualDefaults.visualModelId] and `SemanticDefaults.neuralModelId`).
  static const String modelId = 'mobilenet-v2-features-v1';

  /// Bundled sliced `mobilenetv2` feature graph (Apache-2.0, derived from the
  /// ONNX Model Zoo's `mobilenetv2-12` image classifier — see
  /// `docs/similar-image-search.md` §Model and license). Shipped in the APK
  /// (see `pubspec.yaml`); never downloaded at runtime.
  static const String modelAssetPath =
      'assets/models/mobilenetv2_features.onnx';

  /// Model input side length in pixels (RGB bytes are 224×224×3), shared with
  /// the video classifier's preprocessing (`ImagePreprocessor.mobilenetNchw`).
  static const int inputDimension = 224;

  /// Dimensionality of every stored image-feature vector — the model's
  /// GlobalAveragePool output, sliced off ahead of the 1000-class head.
  static const int dimensions = 1280;

  /// Encoding tag of the persisted vector (`VectorCodec`, little-endian
  /// Float32). A future quantized encoding adds a new tag; rows written with
  /// an unknown tag are treated as stale and regenerated.
  static const String quantizationF32 = 'f32';

  /// Rows embedded per coordinator batch; each batch is persisted before the
  /// next starts (AGENTS.md §12 — bounded memory, resumable).
  static const int batchSize = 8;

  /// Similar images returned per search, sorted most-similar first.
  static const int maxResults = 24;

  /// Cosine floor below which a stored image is excluded even when the pool is
  /// not full. This feature space sits high even for unrelated photos
  /// (measured from the sliced float model: ~0.51 blue-vs-noise, ~0.78
  /// blue-vs-green), so the threshold only rejects content whose embedding is
  /// essentially absent (near-zero norm or degenerate match); the real
  /// precision mechanism is the top-K ranking, which never lets a mid-range
  /// unrelated image push a genuinely similar one out
  /// (`docs/similar-image-search.md` §Similarity and thresholds).
  static const double minSimilarity = 0.4;

  /// Candidate pool multiplier for image retrieval — the SQL fetch is bounded
  /// and vectors are decoded only for this pool.
  static const int candidatePoolMultiple = 2;

  /// Absolute ceiling for the image candidate pool.
  static const int maxCandidatePool = 200;

  /// How long a transient embedding failure cools down before the row is
  /// retried (mirrors the OCR, semantic, and video-visual policies).
  static const int retryCooldownSeconds = 60 * 60;

  /// Maximum stable keys resolved in one deletion-cleanup batch.
  static const int deleteChunkSize = 500;
}

/// Durable lifecycle of one image row (mirrors `VideoVisualStatus` and the
/// embedding statuses).
///
/// * Missing row → not yet embedded.
/// * `completed` rows carry the vector and the `source_revision`/`model_id`
///   they were produced from; a revision or model change makes them stale.
/// * `failed` rows are transient (decode bounce, runtime hiccup) and retry
///   after the cooldown.
/// * `unsupported` rows are terminal (invalid input, zero/out-of-shape vector)
///   and never retried.
enum ImageVisualStatus { completed, failed, unsupported }

/// Reasons an image could not be embedded, mapped to a durable status by the
/// consumer (docs `similar-image-search.md` §Indexing lifecycle).
enum ImageVisualErrorCode {
  /// The decoded pixels produced no usable model input (wrong dimensions,
  /// empty buffer).
  invalidInput,

  /// The runtime produced no usable output (empty logits, model mismatch,
  /// non-finite or zero vector).
  invalidOutput,

  /// The local model runtime is unavailable.
  unavailable,

  /// Any other transient failure (busy, initialization, native error) —
  /// retried after the cooldown.
  failed,
}

class ImageEmbeddingException implements Exception {
  const ImageEmbeddingException(this.code);

  final ImageVisualErrorCode code;

  @override
  String toString() => 'ImageEmbeddingException(${code.name})';
}

/// One image that needs (or may retry) a current feature embedding.
class ImageVisualCandidate {
  const ImageVisualCandidate({
    required this.stableKey,
    required this.sourceRevision,
    required this.contentUri,
  });

  final String stableKey;
  final int sourceRevision;

  /// MediaStore content URI the platform reads pixels from.
  final String contentUri;
}

/// A stored feature embedding that is eligible for reference use: the current
/// model, current dimensions, and a decoded finite vector.
class StoredImageEmbedding {
  const StoredImageEmbedding({
    required this.stableKey,
    required this.sourceRevision,
    required this.modelId,
    required this.dimensions,
    required this.vector,
  });

  final String stableKey;
  final int sourceRevision;
  final String modelId;
  final int dimensions;

  /// L2-normalized vector decoded from the store.
  final List<double> vector;
}

/// One image-vs-reference cosine similarity result (the derived, ranked
/// surface of `image_visual_embeddings`).
class SimilarImageMatch {
  const SimilarImageMatch({required this.stableKey, required this.similarity});

  final String stableKey;

  /// Cosine similarity of the stored vector against the reference vector.
  final double similarity;
}

/// Snapshot of the image vector store for progress surfaces.
class ImageVisualStats {
  const ImageVisualStats({
    required this.total,
    required this.completed,
    required this.failed,
    required this.unsupported,
  });

  /// All embedding rows regardless of model/state.
  final int total;
  final int completed;
  final int failed;
  final int unsupported;
}

/// Runtime lifecycle of one image enrichment run (never persisted).
enum ImageVisualRunStatus {
  idle,
  running,
  completed,
  failed,
  cancelled,

  /// The embedding provider or the pixel source is unavailable. Not an error —
  /// the rest of the pipeline runs unaffected and this run does no work.
  unavailable,
}

/// Progress snapshot emitted at batch granularity (mirrors the OCR/semantic/
/// video coordinators so the UI is not flooded per item).
class ImageVisualRunProgress {
  const ImageVisualRunProgress({
    required this.status,
    required this.processed,
    required this.total,
    required this.succeeded,
    required this.failed,
  });

  final ImageVisualRunStatus status;

  /// Images embedded (or terminally skipped) so far this run.
  final int processed;

  /// Images eligible at run start; 0 means "nothing queued".
  final int total;

  final int succeeded;
  final int failed;

  /// 0..1 share of [total] covered by [processed].
  double get fraction => total == 0 ? 1 : (processed / total).clamp(0.0, 1.0);
}

/// Terminal or interrupted outcome of one image enrichment run.
class ImageVisualRunSummary {
  const ImageVisualRunSummary({
    required this.status,
    this.processed = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.errorMessage,
  });

  final ImageVisualRunStatus status;
  final int processed;
  final int succeeded;
  final int failed;

  /// Set only when the run itself failed (never for per-image outcomes).
  final String? errorMessage;
}
