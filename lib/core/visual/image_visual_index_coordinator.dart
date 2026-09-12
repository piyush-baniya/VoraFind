// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import '../semantic/vector_math.dart' show VectorMath;
import 'image_embedding_provider.dart';
import 'image_pixel_source.dart';
import 'image_visual_models.dart';
import 'image_visual_repository.dart';

/// Drives the image-feature enrichment stage: turns indexed images into
/// bounded, resumable, cancellable embeddings of their local feature vector.
///
/// Wired into the [IndexingCoordinator] as a stage that runs *after* media
/// sync, document extraction, OCR, semantic embedding, and video visual
/// enrichment (docs `similar-image-search.md` §Indexing lifecycle). It is
/// intentionally cheap to construct and stateless across runs: all durable
/// state lives in `image_visual_embeddings`.
///
/// Per image: decode the pixels on the platform (bounding the decode to the
/// model's 224×224 input), embed them via [ImageEmbeddingProvider], and persist
/// the completed vector transactionally. A corrupt/denied image, an unavailable
/// pixel source, or an embedding failure never stops the rest of the image
/// library — the failure is persisted as a durable status
/// (docs `similar-image-search.md` §Failure isolation).
class ImageVisualIndexCoordinator {
  ImageVisualIndexCoordinator({
    required ImageEmbeddingProvider provider,
    required ImagePixelSource pixelSource,
    required ImageVisualIndexRepository repository,
    int batchSize = ImageVisualDefaults.batchSize,
  }) : _provider = provider,
       _pixelSource = pixelSource,
       _repository = repository,
       _batchSize = batchSize;

  final ImageEmbeddingProvider _provider;
  final ImagePixelSource _pixelSource;
  final ImageVisualIndexRepository _repository;
  final int _batchSize;

  bool _cancelled = false;

  /// Cooperative cancellation. The current batch is abandoned; already
  /// persisted embeddings stay valid.
  void cancel() => _cancelled = true;

  /// Runs one image-embedding pass.
  ///
  /// Emits an [ImageVisualRunProgress] per batch and returns a terminal
  /// [ImageVisualRunSummary]. Never throws for per-image failures — those are
  /// recorded as durable statuses. Only a repository-level error that prevents
  /// any work from progressing surfaces as [ImageVisualRunStatus.failed].
  Stream<ImageVisualRunProgress> run() async* {
    if (!_provider.isAvailable) {
      yield const ImageVisualRunProgress(
        status: ImageVisualRunStatus.unavailable,
        processed: 0,
        total: 0,
        succeeded: 0,
        failed: 0,
      );
      return;
    }

    var processed = 0;
    var succeeded = 0;
    var failed = 0;

    try {
      yield ImageVisualRunProgress(
        status: ImageVisualRunStatus.running,
        processed: processed,
        total: 0,
        succeeded: succeeded,
        failed: failed,
      );

      while (!_cancelled) {
        final candidates = await _repository.findImageVisualCandidates(
          batchSize: _batchSize,
          modelId: _provider.modelId,
          nowEpochSeconds: _now(),
        );
        if (candidates.isEmpty) break;

        for (final candidate in candidates) {
          if (_cancelled) break;
          await _embedOne(candidate);
          processed++;
          final status = await _repository.getStatus(candidate.stableKey);
          if (status == ImageVisualStatus.completed) {
            succeeded++;
          } else if (status == ImageVisualStatus.failed ||
              status == ImageVisualStatus.unsupported) {
            failed++;
          }
        }

        yield ImageVisualRunProgress(
          status: ImageVisualRunStatus.running,
          processed: processed,
          total: processed,
          succeeded: succeeded,
          failed: failed,
        );
      }

      final terminal = _cancelled
          ? ImageVisualRunStatus.cancelled
          : ImageVisualRunStatus.completed;
      yield ImageVisualRunProgress(
        status: terminal,
        processed: processed,
        total: processed,
        succeeded: succeeded,
        failed: failed,
      );
    } catch (_) {
      // A repository-level error (not a per-image failure, which _embedOne
      // persists durably) must terminate as a clean terminal status instead of
      // escaping as an unhandled stream error (mirrors Prompt #15.1).
      yield ImageVisualRunProgress(
        status: ImageVisualRunStatus.failed,
        processed: processed,
        total: processed,
        succeeded: succeeded,
        failed: failed,
      );
    }
  }

  Future<void> _embedOne(ImageVisualCandidate candidate) async {
    final key = candidate.stableKey;
    final revision = candidate.sourceRevision;
    final modelId = _provider.modelId;

    // 1. Decode the pixels on the platform, bounded to the model input size. A
    // platform-level failure is durable (transient only when the platform
    // became unavailable). An unexpected platform exception is recorded too —
    // one bad image must never escape _embedOne and abort the whole batch.
    ImagePixelRead read;
    try {
      read = await _pixelSource.readImageRgb(contentUri: candidate.contentUri);
    } catch (_) {
      await _repository.saveFailure(
        stableKey: key,
        sourceRevision: revision,
        modelId: modelId,
        errorCode: ImageVisualErrorCode.failed.name,
        nowEpochSeconds: _now(),
        permanent: false,
      );
      return;
    }
    if (read.errorCode != null) {
      final permanent = read.errorCode != ImagePixelError.platformUnavailable;
      await _repository.saveFailure(
        stableKey: key,
        sourceRevision: revision,
        modelId: modelId,
        errorCode: read.errorCode!,
        nowEpochSeconds: _now(),
        permanent: permanent,
      );
      return;
    }

    // 2. Validate the sample shape before the model sees it: unsupported
    // shapes are terminal (invalidInput), never retried.
    final expectedBytes =
        ImageVisualDefaults.inputDimension *
        ImageVisualDefaults.inputDimension *
        3;
    if (read.rgbBytes.isEmpty ||
        read.rgbBytes.length != expectedBytes ||
        read.width != ImageVisualDefaults.inputDimension ||
        read.height != ImageVisualDefaults.inputDimension) {
      await _repository.saveFailure(
        stableKey: key,
        sourceRevision: revision,
        modelId: modelId,
        errorCode: ImageVisualErrorCode.invalidInput.name,
        nowEpochSeconds: _now(),
        permanent: true,
      );
      return;
    }

    // 3. Embed. Provider exceptions map to durable statuses; only a transient
    // runtime failure retries after the cooldown.
    List<double> vector;
    try {
      vector = await _provider.embed(imageRgbBytes: read.rgbBytes);
    } on ImageEmbeddingException catch (error) {
      final permanent = error.code != ImageVisualErrorCode.failed;
      await _repository.saveFailure(
        stableKey: key,
        sourceRevision: revision,
        modelId: modelId,
        errorCode: error.code.name,
        nowEpochSeconds: _now(),
        permanent: permanent,
      );
      return;
    }

    // 4. Validate the provider contract defensively (AGENTS.md §19): a model
    // that deviates (wrong dimensions, non-finite, zero vector) is a durable
    // invalidOutput, not a crash.
    if (vector.length != ImageVisualDefaults.dimensions ||
        vector.isEmpty ||
        vector.any((v) => v.isNaN || v.isInfinite) ||
        VectorMath.normalized(vector) == null) {
      await _repository.saveFailure(
        stableKey: key,
        sourceRevision: revision,
        modelId: modelId,
        errorCode: ImageVisualErrorCode.invalidOutput.name,
        nowEpochSeconds: _now(),
        permanent: true,
      );
      return;
    }

    await _repository.saveEmbedding(
      stableKey: key,
      sourceRevision: revision,
      modelId: modelId,
      vector: vector,
      nowEpochSeconds: _now(),
    );
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
