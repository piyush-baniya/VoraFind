import 'dart:async';

import 'embedding_provider.dart';
import 'semantic_models.dart';
import 'semantic_repository.dart';
import 'vector_math.dart';

/// Drives the semantic enrichment stage: turns indexed media rows and
/// documents into bounded, resumable, cancellable embedding batches.
///
/// Wired into the [IndexingCoordinator] as the stage that runs *after* media
/// sync, document extraction, and OCR (docs `semantic-search.md` §Indexing
/// lifecycle). It is intentionally cheap to construct and stateless across
/// runs: all durable state lives in `semantic_embeddings`.
///
/// Behavior:
/// * Pages candidates via [SemanticIndexRepository.findEmbeddingCandidates]
///   (missing, stale, or failed-past-cooldown rows).
/// * Embeds each candidate's deterministic representation via the injected
///   [EmbeddingProvider].
/// * Persists each successful embedding, or a durable failed/unsupported
///   status on error.
/// * Honors cancellation between batches — completed batches stay valid.
/// * If the provider is unavailable, the run concludes as
///   [SemanticRunStatus.unavailable] and does no work (the rest of the
///   pipeline is unaffected).
class SemanticIndexCoordinator {
  SemanticIndexCoordinator({
    required this._provider,
    required this._repository,
    this._batchSize = SemanticDefaults.batchSize,
  });

  final EmbeddingProvider _provider;
  final SemanticIndexRepository _repository;
  final int _batchSize;

  bool _cancelled = false;

  /// Cooperative cancellation. The current batch is abandoned; already
  /// persisted embeddings stay valid.
  void cancel() => _cancelled = true;

  /// Runs one semantic enrichment pass.
  ///
  /// Emits a [SemanticRunProgress] per batch and returns a terminal
  /// [SemanticRunSummary]. Never throws for per-row failures — those are
  /// recorded as durable failed statuses. Only a repository-level error that
  /// prevents any work from progressing surfaces as
  /// [SemanticRunStatus.failed].
  Stream<SemanticRunProgress> run() async* {
    if (!_provider.isAvailable) {
      yield const SemanticRunProgress(
        status: SemanticRunStatus.unavailable,
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

    yield SemanticRunProgress(
      status: SemanticRunStatus.running,
      processed: processed,
      total: 0,
      succeeded: succeeded,
      failed: failed,
    );

    while (!_cancelled) {
      final candidates = await _repository.findEmbeddingCandidates(
        batchSize: _batchSize,
        modelId: _provider.modelId,
        dimensions: _provider.dimensions,
        nowEpochSeconds: _now(),
      );
      if (candidates.isEmpty) break;

      for (final candidate in candidates) {
        if (_cancelled) break;
        await _embedOne(candidate);
        processed++;
        // Success vs failure is tracked inside _embedOne via status writes;
        // we approximate succeeded/failed from the persisted status.
        final status = await _repository.getStatus(
          candidate.stableKey,
          candidate.contentType,
        );
        if (status == SemanticEmbeddingStatus.completed) {
          succeeded++;
        } else if (status == SemanticEmbeddingStatus.failed ||
            status == SemanticEmbeddingStatus.unsupported) {
          failed++;
        }
      }

      yield SemanticRunProgress(
        status: SemanticRunStatus.running,
        processed: processed,
        total: processed,
        succeeded: succeeded,
        failed: failed,
      );
    }

    final terminal = _cancelled
        ? SemanticRunStatus.cancelled
        : SemanticRunStatus.completed;
    yield SemanticRunProgress(
      status: terminal,
      processed: processed,
      total: processed,
      succeeded: succeeded,
      failed: failed,
    );
  }

  Future<void> _embedOne(SemanticCandidate candidate) async {
    final input = candidate.contentType == SemanticContentType.media
        ? SemanticInputBuilder.forMedia(
            displayName: candidate.displayName,
            relativePath: candidate.relativePath,
            ocrText: candidate.text,
            isScreenshot: candidate.isScreenshot,
          )
        : SemanticInputBuilder.forDocument(
            displayName: candidate.displayName,
            relativePath: candidate.relativePath,
            extractedText: candidate.text,
          );

    try {
      final vector = await _provider.embed(input);
      // Validate the embedding: correct dimensions, all finite, non-zero norm.
      // A deterministic provider can return a zero vector for empty/stopword-
      // only input; persist as unsupported rather than storing an unusable row
      // that would silently produce null similarity at search time.
      if (vector.length != _provider.dimensions ||
          vector.any((v) => v.isNaN || v.isInfinite) ||
          VectorMath.normalized(vector) == null) {
        await _repository.saveFailure(
          stableKey: candidate.stableKey,
          contentType: candidate.contentType,
          sourceRevision: candidate.sourceRevision,
          modelId: _provider.modelId,
          errorCode: EmbeddingErrorCode.invalidOutput.name,
          nowEpochSeconds: _now(),
          permanent: true,
        );
        return;
      }
      await _repository.saveEmbedding(
        stableKey: candidate.stableKey,
        contentType: candidate.contentType,
        sourceRevision: candidate.sourceRevision,
        modelId: _provider.modelId,
        vector: vector,
        nowEpochSeconds: _now(),
      );
    } on EmbeddingException catch (e) {
      await _repository.saveFailure(
        stableKey: candidate.stableKey,
        contentType: candidate.contentType,
        sourceRevision: candidate.sourceRevision,
        modelId: _provider.modelId,
        errorCode: e.code.name,
        nowEpochSeconds: _now(),
        permanent: e.code == EmbeddingErrorCode.unsupportedInput,
      );
    } catch (_) {
      await _repository.saveFailure(
        stableKey: candidate.stableKey,
        contentType: candidate.contentType,
        sourceRevision: candidate.sourceRevision,
        modelId: _provider.modelId,
        errorCode: EmbeddingErrorCode.failed.name,
        nowEpochSeconds: _now(),
        permanent: false,
      );
    }
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
