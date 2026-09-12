// ignore_for_file: prefer_initializing_formals
import '../database/app_database.dart' show MediaItem;
import '../database/media_repository.dart' show MediaRepository;
import '../visual/image_embedding_provider.dart';
import '../visual/image_pixel_source.dart';
import '../visual/image_visual_models.dart';
import '../visual/image_visual_repository.dart';

/// Where the similar-image reference came from.
enum SimilarImageSource {
  /// An already-indexed image (Flow A): the stored embedding is reused, no
  /// pixels are decoded.
  indexed,

  /// An externally picked image (Flow B): pixels are decoded once and embedded
  /// ephemerally — never persisted, never indexed.
  picked,
}

/// The image a similarity search is run against.
class SimilarImageReference {
  const SimilarImageReference({
    required this.contentUri,
    required this.displayName,
    this.stableKey,
    this.relativePath,
    this.dateModified,
    this.imageWidth,
    this.imageHeight,
  });

  /// Content URI the reference pixels can be read from (also drives the
  /// preview thumbnail).
  final String contentUri;

  /// Display name for the header.
  final String displayName;

  /// Stable key when the reference is an indexed media row (Flow A); null for
  /// a picked external image (Flow B).
  final String? stableKey;

  final String? relativePath;
  final int? dateModified;
  final int? imageWidth;
  final int? imageHeight;

  bool get isIndexed => stableKey != null;
}

/// One similar image found for a reference.
class SimilarImageResult {
  const SimilarImageResult({
    required this.stableKey,
    required this.similarity,
    required this.contentUri,
    required this.displayName,
    this.relativePath,
    this.dateModified,
    this.imageWidth,
    this.imageHeight,
  });

  final String stableKey;

  /// Cosine similarity of the stored image-feature vector against the
  /// reference, in `[0, 1]`.
  final double similarity;

  final String contentUri;
  final String displayName;
  final String? relativePath;
  final int? dateModified;
  final int? imageWidth;
  final int? imageHeight;
}

/// Outcome of one similarity search: the reference plus the ranked results.
class SimilarImageOutcome {
  const SimilarImageOutcome({required this.reference, this.results = const []});

  final SimilarImageReference reference;
  final List<SimilarImageResult> results;

  bool get isEmpty => results.isEmpty;
}

/// Why a similarity search could not produce results.
enum SimilarImageErrorCode {
  /// Flow A: the reference has no usable stored embedding (not indexed yet,
  /// model changed, or its row failed).
  notIndexed,

  /// The reference pixels could not be decoded or embedded (corrupt, denied,
  /// unsupported input).
  decodeFailed,

  /// The local image model or pixel bridge is unavailable.
  unavailable,

  /// Any other transient failure.
  failed,
}

class SimilarImageException implements Exception {
  const SimilarImageException(this.error);

  final SimilarImageErrorCode error;

  @override
  String toString() => 'SimilarImageException(${error.name})';
}

/// Local, bounded image-to-image similarity search (docs
/// `similar-image-search.md`).
///
/// Composes the image vector store, the embedding provider, the pixel source,
/// and the media repository behind the two reference flows:
///
/// * **Flow A (indexed image)** — [SimilarImageReference.stableKey] is set;
///   the stored, current-model embedding is reused and the reference is
///   excluded from the results by stable key.
/// * **Flow B (picked image)** — only a content URI is known; pixels are
///   decoded once, embedded ephemerally in memory, and never persisted, so a
///   picked image can never become part of the index by accident.
///
/// Retrieval is bounded (capped pool, top-K, deterministic tie-break) inside
/// the repository; this layer only shapes the matches into displayable results
/// and guards against the reference matching itself by URI.
class SimilarImageService {
  const SimilarImageService({
    required ImageVisualSearchRepository searchRepository,
    required ImageEmbeddingProvider embeddingProvider,
    required ImagePixelSource pixelSource,
    required MediaRepository mediaRepository,
    int maxResults = ImageVisualDefaults.maxResults,
  }) : _searchRepository = searchRepository,
       _embeddingProvider = embeddingProvider,
       _pixelSource = pixelSource,
       _mediaRepository = mediaRepository,
       _maxResults = maxResults;

  final ImageVisualSearchRepository _searchRepository;
  final ImageEmbeddingProvider _embeddingProvider;
  final ImagePixelSource _pixelSource;
  final MediaRepository _mediaRepository;
  final int _maxResults;

  /// Runs a similarity search against [reference].
  ///
  /// Resolves the reference embedding (stored for Flow A, freshly computed for
  /// Flow B), retrieves the top-K similar images, and shapes them with the
  /// media rows. Throws [SimilarImageException] when the reference has no
  /// usable embedding or cannot be decoded.
  Future<SimilarImageOutcome> findSimilar({
    required SimilarImageReference reference,
  }) async {
    final modelId = _embeddingProvider.modelId;
    final dimensions = _embeddingProvider.dimensions;

    final vector = await _referenceVector(reference, modelId, dimensions);

    final matches = await _searchRepository.findSimilarImages(
      referenceVector: vector,
      modelId: modelId,
      dimensions: dimensions,
      maxResults: _maxResults,
      minSimilarity: ImageVisualDefaults.minSimilarity,
      excludeStableKey: reference.stableKey,
    );
    if (matches.isEmpty) {
      return SimilarImageOutcome(reference: reference);
    }

    final items = await _mediaRepository.fetchByStableKeys(
      matches.map((m) => m.stableKey),
    );
    final byKey = {for (final item in items) item.stableKey: item};

    final results = <SimilarImageResult>[];
    for (final match in matches) {
      final item = byKey[match.stableKey];
      if (item == null) continue;
      // Self-match guard: a picked reference that is already indexed must not
      // be returned as its own, trivially-identical "result".
      if (item.contentUri == reference.contentUri) continue;
      results.add(_shape(item, match.similarity));
    }
    return SimilarImageOutcome(reference: reference, results: results);
  }

  Future<List<double>> _referenceVector(
    SimilarImageReference reference,
    String modelId,
    int dimensions,
  ) async {
    if (reference.isIndexed) {
      // Flow A: reuse the stored embedding; never re-embed file contents that
      // were already enriched (bounded, resumable indexing stays the only
      // vector writer).
      final stored = await _searchRepository.getCurrentEmbedding(
        stableKey: reference.stableKey!,
        modelId: modelId,
        dimensions: dimensions,
      );
      if (stored == null) {
        throw const SimilarImageException(SimilarImageErrorCode.notIndexed);
      }
      return stored.vector;
    }

    // Flow B: decode once, embed ephemerally.
    ImagePixelRead read;
    try {
      read = await _pixelSource.readImageRgb(contentUri: reference.contentUri);
    } catch (_) {
      // A throwing platform read must not crash the search flow (mirrors the
      // index coordinator's per-item isolation, AGENTS.md §19).
      throw const SimilarImageException(SimilarImageErrorCode.failed);
    }
    if (read.errorCode != null) {
      throw _pixelError(read.errorCode!);
    }
    try {
      return await _embeddingProvider.embed(imageRgbBytes: read.rgbBytes);
    } on ImageEmbeddingException catch (error) {
      throw switch (error.code) {
        ImageVisualErrorCode.invalidInput ||
        ImageVisualErrorCode.invalidOutput => const SimilarImageException(
          SimilarImageErrorCode.decodeFailed,
        ),
        ImageVisualErrorCode.unavailable => const SimilarImageException(
          SimilarImageErrorCode.unavailable,
        ),
        ImageVisualErrorCode.failed => const SimilarImageException(
          SimilarImageErrorCode.failed,
        ),
      };
    }
  }

  SimilarImageException _pixelError(String code) {
    if (code == ImagePixelError.platformUnavailable) {
      return const SimilarImageException(SimilarImageErrorCode.unavailable);
    }
    if (code == ImagePixelError.corrupt ||
        code == ImagePixelError.denied ||
        code == ImagePixelError.invalidContentUri ||
        code == ImagePixelError.unsupported) {
      return const SimilarImageException(SimilarImageErrorCode.decodeFailed);
    }
    return const SimilarImageException(SimilarImageErrorCode.failed);
  }

  static SimilarImageResult _shape(MediaItem item, double similarity) {
    return SimilarImageResult(
      stableKey: item.stableKey,
      similarity: similarity,
      contentUri: item.contentUri,
      displayName: item.displayName,
      relativePath: item.relativePath,
      dateModified: item.dateModified,
      imageWidth: item.width,
      imageHeight: item.height,
    );
  }
}
