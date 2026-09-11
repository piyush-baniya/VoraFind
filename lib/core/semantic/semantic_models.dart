import 'package:drift/drift.dart' show TypeConverter;

import '../search/search_normalizer.dart';

/// Bounds and policy constants for the local semantic subsystem
/// (`docs/semantic-search.md`). Every value exists to keep embedding
/// generation and retrieval bounded on real phones.
abstract final class SemanticDefaults {
  /// Rows embedded per coordinator batch; each batch is persisted before the
  /// next starts (AGENTS.md §12 — bounded memory, resumable).
  static const int batchSize = 8;

  /// Hard cap on the representation string fed to a model. Bounded inputs
  /// keep latency and memory predictable regardless of how large an extracted
  /// document or OCR payload grew (Prompt #9 already caps stored text; this
  /// is the embedding-side cap).
  static const int maxInputChars = 4000;

  /// Semantic candidates below this cosine similarity never surface. Tuned so
  /// near-zero-overlap noise is excluded; a real model re-tunes this constant
  /// (single knob, documented in `docs/semantic-search.md`).
  static const double minSimilarity = 0.35;

  /// Rank points a similarity of 1.0 would contribute on top of the keyword
  /// score. Deliberately *below* the weakest exact single-token filename hit
  /// (displayName 50 × exact 3 = 150) and below title/OCR exact hits, so an
  /// exact keyword match always beats a semantic-only match, while a strong
  /// semantic match still outranks the weakest OCR substring hits (20). See
  /// `docs/semantic-search.md` §Hybrid ranking.
  static const int semanticRankWeight = 30;

  /// Candidate pool multiplier for semantic retrieval — the SQL fetch is
  /// bounded and vectors are decoded only for this pool.
  static const int candidatePoolMultiple = 2;

  /// Absolute ceiling for the semantic candidate pool.
  static const int maxCandidatePool = 200;

  /// How long a transient embedding failure cools down before the row is
  /// retried (mirrors the OCR policy).
  static const int retryCooldownSeconds = 60 * 60;

  /// Storage tag of the vector encoding persisted today: little-endian
  /// Float32 bytes. A future quantized encoding adds a new tag; rows written
  /// with an unknown tag are treated as stale and regenerated.
  static const String quantizationF32 = 'f32';
}

/// Which indexed surface a semantic embedding represents.
///
/// Polymorphic by design: media rows and SAF documents share one vector store
/// keyed by stable identity, and future segment-level types (video segments,
/// audio segments — explicitly out of scope for this prompt) can join without
/// a schema redesign.
enum SemanticContentType { media, document }

class SemanticContentTypeConverter
    extends TypeConverter<SemanticContentType, String> {
  const SemanticContentTypeConverter();

  @override
  String toSql(SemanticContentType value) => value.name;

  @override
  SemanticContentType fromSql(String fromDb) =>
      SemanticContentType.values.asNameMap()[fromDb] ??
      SemanticContentType.media;
}

/// Durable lifecycle of one embedding row (mirrors the OCR/content statuses).
///
/// * Missing row → not yet embedded.
/// * `completed` rows carry the vector and the `source_revision`/`model_id`
///   they were produced from; a revision or model change makes them stale.
/// * `failed` rows are transient (runtime hiccup, busy) and retry after the
///   cooldown.
/// * `unsupported` rows are terminal (empty input, zero vector) and never
///   retried.
enum SemanticEmbeddingStatus { completed, failed, unsupported }

/// One bounded, deterministic semantic input for embedding.
///
/// Built exclusively from already-indexed, already-derived text (filenames,
/// metadata, current OCR/document text) — never from raw files. The same
/// indexed content always produces the same representation, so re-embedding
/// is only ever triggered by staleness, never by nondeterminism.
abstract final class SemanticInputBuilder {
  /// Canonicalizes and bounds [parts], dropping empty ones. The join order is
  /// caller-defined and stable.
  static String build(Iterable<String?> parts) {
    final canonical = SearchNormalizer.canonical(
      [
        for (final part in parts)
          if (part != null && part.isNotEmpty) part,
      ].join(' '),
    );
    if (canonical.length <= SemanticDefaults.maxInputChars) {
      return canonical;
    }
    return canonical.substring(0, SemanticDefaults.maxInputChars);
  }

  /// Media representation (images only today): filename + path + current OCR
  /// text, with the screenshot context folded in as a marker word so
  /// screenshots and ordinary photos remain distinguishable to the model.
  static String forMedia({
    required String displayName,
    String? relativePath,
    String? ocrText,
    required bool? isScreenshot,
  }) {
    return build([
      displayName,
      relativePath,
      isScreenshot == true ? 'screenshot context' : null,
      ocrText,
    ]);
  }

  /// Document representation: filename + path + extracted text.
  static String forDocument({
    required String displayName,
    String? relativePath,
    required String? extractedText,
  }) {
    return build([displayName, relativePath, extractedText]);
  }
}

/// A semantic retrieval hit: the matched stable identity plus its cosine
/// similarity in `[-1, 1]` (typically `[0, 1]` after normalization).
class SemanticMatch {
  const SemanticMatch({
    required this.stableKey,
    required this.contentType,
    required this.similarity,
  });

  final String stableKey;
  final SemanticContentType contentType;

  /// Cosine similarity of the stored vector against the query vector.
  final double similarity;
}

/// Snapshot of the semantic vector store for progress surfaces.
class SemanticStats {
  const SemanticStats({
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

/// Runtime lifecycle of one semantic enrichment run (never persisted).
enum SemanticRunStatus {
  idle,
  running,
  completed,
  failed,
  cancelled,

  /// The embedding provider is unavailable (no local model shipped yet, or
  /// initialization failed). Not an error — the rest of the pipeline is
  /// unaffected and this run does no work.
  unavailable,
}

/// Progress snapshot emitted at batch granularity (mirrors the OCR and
/// document coordinators so the UI is not flooded per item).
class SemanticRunProgress {
  const SemanticRunProgress({
    required this.status,
    required this.processed,
    required this.total,
    required this.succeeded,
    required this.failed,
  });

  final SemanticRunStatus status;

  /// Rows embedded (or terminally skipped) so far this run.
  final int processed;

  /// Rows eligible at run start; 0 means "nothing queued".
  final int total;

  final int succeeded;
  final int failed;

  /// 0..1 share of [total] covered by [processed].
  double get fraction => total == 0 ? 1 : (processed / total).clamp(0.0, 1.0);
}

/// Terminal or interrupted outcome of one semantic enrichment run.
class SemanticRunSummary {
  const SemanticRunSummary({
    required this.status,
    this.processed = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.errorMessage,
  });

  final SemanticRunStatus status;
  final int processed;
  final int succeeded;
  final int failed;

  /// Set only when the run itself failed (never for per-row outcomes).
  final String? errorMessage;
}
