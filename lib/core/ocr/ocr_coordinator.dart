import 'dart:async';

import '../database/app_database.dart' show MediaItem;
import '../database/media_repository.dart';
import 'ocr_detector.dart';
import 'ocr_models.dart';

/// Snapshot of one OCR run, emitted at batch granularity (mirrors how the
/// discovery engine reports progress, so the UI is not flooded per image).
class OcrRunProgress {
  const OcrRunProgress({
    required this.status,
    required this.processed,
    required this.total,
    required this.succeeded,
    required this.failed,
  });

  final OcrRunStatus status;

  /// Rows recognized so far this run.
  final int processed;

  /// Image rows eligible at run start (the denominator for progress). 0 means
  /// "nothing queued"; treat that as fully done rather than a divide-by-zero.
  final int total;

  final int succeeded;
  final int failed;

  /// 0..1 share of [total] covered by [processed].
  double get fraction => total == 0 ? 1 : (processed / total).clamp(0.0, 1.0);
}

/// Terminal or interrupted outcome of one [OcrCoordinator.start] call.
class OcrRunSummary {
  const OcrRunSummary({
    required this.status,
    this.processed = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.errorMessage,
  });

  final OcrRunStatus status;
  final int processed;
  final int succeeded;
  final int failed;

  /// Set only when the run itself failed (not for ordinary per-row outcomes).
  final String? errorMessage;
}

/// Drives the on-device OCR pipeline (docs `ocr.md`, AGENTS.md §22).
///
/// One run drains the pending queue by repeatedly calling
/// [MediaRepository.findOcrCandidates] and recognizing each candidate over the
/// native [OcrDetector]. Per-row failures are **expected** and never fail the
/// run (AGENTS.md §19): transient problems store [OcrStatus.failed] (retried
/// after the cooldown by a later run) and undecodable bytes store
/// [OcrStatus.unsupported] (never retried). Cancellation is cooperative and
/// checked between candidates, so the app going to the background can stop the
/// work instead of chewing battery (AGENTS.md §22).
class OcrCoordinator {
  OcrCoordinator({
    required this.repository,
    required this.detector,
    this.batchSize = OcrDefaults.batchSize,
    this.maxImageDimension = 2048,
    this.nowSeconds,
  });

  final MediaRepository repository;
  final OcrDetector detector;

  /// How many rows one [findOcrCandidates] batch drains.
  final int batchSize;

  /// Decoded-dimension cap handed to the native recognizer.
  final int maxImageDimension;

  /// Injectable clock for deterministic tests (epoch seconds).
  final int Function()? nowSeconds;

  final StreamController<OcrRunProgress> _progress =
      StreamController<OcrRunProgress>.broadcast();

  /// Latest progress across runs (status, counts) — the single UI-visible
  /// snapshot; survives recomputing `_lastTotal` so a finished "N images"
  /// line stays honest until the next run starts.
  Stream<OcrRunProgress> get progress => _progress.stream;

  bool _running = false;
  bool _cancelRequested = false;

  OcrRunProgress? _last;

  bool get isRunning => _running;

  /// Last emitted snapshot; null before the first run.
  OcrRunProgress? get lastProgress => _last;

  int _now() => (nowSeconds ?? _defaultNowSeconds)();

  /// Starts a single run that drains the pending queue. Safe to call at any
  /// time: while a run is active this returns `running` immediately without
  /// queuing up a second run (the phone would otherwise pile up re-runs on
  /// every lifecycle resume).
  Future<OcrRunSummary> start() async {
    if (_running) return const OcrRunSummary(status: OcrRunStatus.running);

    _running = true;
    _cancelRequested = false;
    var processed = 0;
    var succeeded = 0;
    var failed = 0;
    var total = 0;
    try {
      total = (await repository.ocrStats()).eligible;
      _emit(OcrRunStatus.running, processed, total, succeeded, failed);

      while (!_cancelRequested) {
        final candidates = await repository.findOcrCandidates(
          batchSize: batchSize,
          nowEpochSeconds: _now(),
        );
        if (candidates.isEmpty) break;
        for (final candidate in candidates) {
          if (_cancelRequested) break;
          if (await _recognizeOne(candidate)) {
            succeeded++;
          } else {
            failed++;
          }
          processed++;
        }
        _emit(OcrRunStatus.running, processed, total, succeeded, failed);
      }

      final status = _cancelRequested
          ? OcrRunStatus.cancelled
          : OcrRunStatus.completed;
      return _finish(
        status: status,
        processed: processed,
        total: total,
        succeeded: succeeded,
        failed: failed,
      );
    } catch (error) {
      return _finish(
        status: OcrRunStatus.failed,
        processed: processed,
        total: total,
        succeeded: succeeded,
        failed: failed,
        errorMessage: 'Text extraction failed (${error.runtimeType}).',
      );
    } finally {
      _running = false;
    }
  }

  /// Cooperative cancellation. The run stops at the next candidate boundary
  /// and reports [OcrRunStatus.cancelled]. Idempotent.
  void cancel() {
    _cancelRequested = true;
  }

  /// Recognizes one candidate and persists its durable status. Returns whether
  /// the recognition succeeded. Never throws — a native error is mapped to a
  /// durable `failed`/`unsupported` row instead (the pipeline must survive
  /// individual bad files, AGENTS.md §13/§19).
  Future<bool> _recognizeOne(MediaItem candidate) async {
    try {
      final result = await detector.recognizeText(
        candidate.contentUri,
        maxWidth: maxImageDimension,
      );
      await repository.saveOcrResult(
        stableKey: candidate.stableKey,
        text: result.text,
        status: OcrStatus.completed,
        sourceRevision: candidate.metadataRevision,
        nowEpochSeconds: _now(),
      );
      return true;
    } on OcrRecognitionException catch (error) {
      // Undecodable bytes are proven permanent; everything else is transient
      // (gone/revoked URI, recognizer hiccup, busy) and retried after cooldown.
      final status = error.code == OcrErrorCode.decodeFailed
          ? OcrStatus.unsupported
          : OcrStatus.failed;
      await repository.saveOcrResult(
        stableKey: candidate.stableKey,
        text: null,
        status: status,
        sourceRevision: candidate.metadataRevision,
        nowEpochSeconds: _now(),
        errorCode: error.code.name,
      );
      return false;
    }
  }

  OcrRunSummary _finish({
    required OcrRunStatus status,
    required int processed,
    required int total,
    required int succeeded,
    required int failed,
    String? errorMessage,
  }) {
    _emit(status, processed, total, succeeded, failed);
    return OcrRunSummary(
      status: status,
      processed: processed,
      succeeded: succeeded,
      failed: failed,
      errorMessage: errorMessage,
    );
  }

  void _emit(
    OcrRunStatus status,
    int processed,
    int total,
    int succeeded,
    int failed,
  ) {
    final snapshot = OcrRunProgress(
      status: status,
      processed: processed,
      total: total,
      succeeded: succeeded,
      failed: failed,
    );
    _last = snapshot;
    _progress.add(snapshot);
  }

  static int _defaultNowSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
