// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'video_frame_sampler.dart';
import 'visual_frame_classifier.dart';
import 'visual_models.dart';
import 'visual_repository.dart';

/// Drives the video visual enrichment stage: turns indexed videos into
/// bounded, resumable, cancellable frame-classification batches.
///
/// Wired into the [IndexingCoordinator] as the stage that runs *after* media
/// sync, document extraction, OCR, and semantic embedding (docs
/// `video-visual-search.md` §Indexing lifecycle). It is intentionally cheap to
/// construct and stateless across runs: all durable state lives in
/// `video_visual_status` / `video_visual_frames`.
///
/// Per video: sample at most [VisualDefaults.maxFramesPerVideo] frames on the
/// platform, classify each via [VisualFrameClassifier], aggregate the findings,
/// and persist them (transactionally) as completed-status + frame rows. A
/// corrupt/DRM video, an unavailable sampler, or a classification failure never
/// stops the rest of the video library — the failure is persisted as a durable
/// status (docs `video-visual-search.md` §Failure isolation).
class VisualIndexCoordinator {
  VisualIndexCoordinator({
    required VisualFrameClassifier classifier,
    required VideoFrameSampler sampler,
    required VisualIndexRepository repository,
    int batchSize = VisualDefaults.batchSize,
  }) : _classifier = classifier,
       _sampler = sampler,
       _repository = repository,
       _batchSize = batchSize;

  final VisualFrameClassifier _classifier;
  final VideoFrameSampler _sampler;
  final VisualIndexRepository _repository;
  final int _batchSize;

  bool _cancelled = false;

  /// Cooperative cancellation. The current batch is abandoned; already
  /// persisted analysis stays valid.
  void cancel() => _cancelled = true;

  /// Runs one visual enrichment pass.
  ///
  /// Emits a [VisualRunProgress] per batch and returns a terminal
  /// [VisualRunSummary]. Never throws for per-video failures — those are
  /// recorded as durable statuses. Only a repository-level error that prevents
  /// any work from progressing surfaces as [VisualRunStatus.failed].
  Stream<VisualRunProgress> run() async* {
    if (!_classifier.isAvailable) {
      yield const VisualRunProgress(
        status: VisualRunStatus.unavailable,
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
      yield VisualRunProgress(
        status: VisualRunStatus.running,
        processed: processed,
        total: 0,
        succeeded: succeeded,
        failed: failed,
      );

      while (!_cancelled) {
        final candidates = await _repository.findVisualCandidates(
          batchSize: _batchSize,
          modelId: _classifier.modelId,
          nowEpochSeconds: _now(),
        );
        if (candidates.isEmpty) break;

        for (final candidate in candidates) {
          if (_cancelled) break;
          await _analyzeOne(candidate);
          processed++;
          final status = await _repository.getStatus(candidate.stableKey);
          if (status == VisualVideoStatus.completed) {
            succeeded++;
          } else if (status == VisualVideoStatus.failed ||
              status == VisualVideoStatus.unsupported) {
            failed++;
          }
        }

        yield VisualRunProgress(
          status: VisualRunStatus.running,
          processed: processed,
          total: processed,
          succeeded: succeeded,
          failed: failed,
        );
      }

      final terminal = _cancelled
          ? VisualRunStatus.cancelled
          : VisualRunStatus.completed;
      yield VisualRunProgress(
        status: terminal,
        processed: processed,
        total: processed,
        succeeded: succeeded,
        failed: failed,
      );
    } catch (_) {
      // A repository-level error (not a per-video failure, which _analyzeOne
      // persists durably) must terminate as a clean terminal status instead of
      // escaping as an unhandled stream error (Prompt #15.1).
      yield VisualRunProgress(
        status: VisualRunStatus.failed,
        processed: processed,
        total: processed,
        succeeded: succeeded,
        failed: failed,
      );
    }
  }

  Future<void> _analyzeOne(VisualCandidate candidate) async {
    final key = candidate.stableKey;
    final revision = candidate.sourceRevision;
    final modelId = _classifier.modelId;

    // 1. Sample frames on the platform. A platform-level failure is durable
    // (transient only when the platform became unavailable).
    final sampling = await _sampler.sampleFrames(
      contentUri: candidate.contentUri,
    );
    if (sampling.errorCode != null) {
      final permanent =
          sampling.errorCode != VisualSamplerError.platformUnavailable;
      await _repository.saveFailure(
        stableKey: key,
        sourceRevision: revision,
        modelId: modelId,
        errorCode: sampling.errorCode!,
        nowEpochSeconds: _now(),
        permanent: permanent,
      );
      return;
    }

    // 2. A video with frames that produced no concepts is still "completed"
    // (recognizable-content detection, not an error). Zero frames means the
    // sampler yielded nothing — persist a terminal unsupported row.
    if (sampling.frames.isEmpty) {
      await _repository.saveFailure(
        stableKey: key,
        sourceRevision: revision,
        modelId: modelId,
        errorCode: VisualErrorCode.invalidInput.name,
        nowEpochSeconds: _now(),
        permanent: true,
      );
      return;
    }

    // 3. Classify each frame, bounding per-video model work to the sampled
    // frames (never a search-time decode, never the whole video).
    final analyzed = <AnalyzedVisualFrame>[];
    for (var index = 0; index < sampling.frames.length; index++) {
      if (_cancelled) return;
      final frame = sampling.frames[index];
      try {
        final classification = await _classifier.classify(
          rgbBytes: frame.rgbBytes,
        );
        analyzed.add(
          AnalyzedVisualFrame(
            frameIndex: index,
            frameTsMs: frame.frameTsMs,
            concepts: classification.concepts,
          ),
        );
      } on VisualClassificationException catch (error) {
        await _repository.saveFailure(
          stableKey: key,
          sourceRevision: revision,
          modelId: modelId,
          errorCode: error.code.name,
          nowEpochSeconds: _now(),
          permanent: error.code == VisualErrorCode.unavailable,
        );
        return;
      }
    }

    await _repository.saveAnalysis(
      stableKey: key,
      sourceRevision: revision,
      modelId: modelId,
      frames: analyzed,
      nowEpochSeconds: _now(),
    );
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
