import 'dart:async';

import '../database/media_repository.dart' show MediaIndexStats;
import '../database/synchronization_coordinator.dart';
import '../documents/document_coordinator.dart';
import '../documents/document_models.dart' show DocumentRunStatus;
import '../ocr/ocr_coordinator.dart';
import '../ocr/ocr_models.dart';
import '../platform/content_access_models.dart';
import '../semantic/semantic_index_coordinator.dart';
import '../semantic/semantic_models.dart';

/// High-level lifecycle of the whole indexing pipeline (docs
/// `android-indexing-architecture.md` §Lifecycle, Prompt #10).
///
/// Exactly one abstraction for every indexing surface: media synchronization,
/// SAF document discovery/extraction, and OCR enrichment all report through
/// [IndexingStatus]; the Home screen renders this state and nothing else.
enum IndexingPhase {
  /// No indexing run is active and none has concluded yet.
  idle,

  /// A run started (planning units, checking access).
  preparing,

  /// MediaStore discovery/persistence is running (media scan).
  discovering,

  /// A media scan unit just concluded; counts are being recorded.
  persisting,

  /// Document extraction and/or OCR enrichment is running.
  enriching,

  /// The last run concluded cleanly. Progress counts stay available.
  completed,

  /// The last run was cancelled (app backgrounded or explicit request).
  cancelled,

  /// The last run failed (no access, or a stage error).
  failed,
}

/// One UI-visible snapshot of the indexing pipeline.
///
/// Counts are honest or absent: a field is null when the underlying stage
/// cannot provide a reliable total (AGENTS.md §18 — never fake progress).
class IndexingStatus {
  const IndexingStatus({
    required this.phase,
    this.mediaIndexed,
    this.mediaChanged,
    this.contentProcessed,
    this.contentTotal,
    this.documentsProcessed,
    this.documentsTotal,
    this.semanticProcessed,
    this.semanticTotal,
    this.message,
  });

  const IndexingStatus.idle() : this(phase: IndexingPhase.idle);

  final IndexingPhase phase;

  /// Total media rows in the index (after a synchronization stage ran).
  final int? mediaIndexed;

  /// Media rows inserted or updated by the last synchronization stage.
  final int? mediaChanged;

  /// OCR enrichment progress (processed/total image rows).
  final int? contentProcessed;
  final int? contentTotal;

  /// Document extraction progress (processed/total document rows).
  final int? documentsProcessed;
  final int? documentsTotal;

  /// Semantic embedding progress (processed/total eligible rows). Null when
  /// the semantic provider is unavailable.
  final int? semanticProcessed;
  final int? semanticTotal;

  /// Short, user-safe explanation for [IndexingPhase.failed] runs. Never
  /// contains stack traces or user content.
  final String? message;

  bool get isRunning =>
      phase == IndexingPhase.preparing ||
      phase == IndexingPhase.discovering ||
      phase == IndexingPhase.persisting ||
      phase == IndexingPhase.enriching;
}

/// The pipeline's media-synchronization stage, functionally abstracted so the
/// coordinator is testable without the platform.
abstract interface class IndexingMediaSync {
  Future<SyncSessionResult> run(List<ContentCategory> categories);
  Future<void> cancel();
}

/// Drives one full indexing run: media sync → documents → OCR → semantic.
///
/// Composes the existing coordinators behind a single [IndexingStatus] stream
/// without replacing them (AGENTS.md §2/§29). A run:
///
/// 1. runs `IndexingMediaSync` over every media category,
/// 2. drains the document extraction queue,
/// 3. drains the OCR queue,
/// 4. drains the semantic embedding queue (if a provider is available),
/// 5. reports [IndexingPhase.completed] (or cancelled/failed).
///
/// Failure isolation: per-file failures never reach this coordinator — the
/// sub-coordinators persist durable failed/unsupported rows instead. Only a
/// stage-level failure (no access, DB error) fails the run. A semantic-stage
/// failure is non-fatal: metadata/OCR/document search continue working.
///
/// Cancellation is cooperative at stage boundaries; work persisted before the
/// request remains valid, and no checkpoint is written for incomplete units.
class IndexingCoordinator {
  IndexingCoordinator({
    required this.mediaSync,
    required this.runDocuments,
    required this.cancelDocuments,
    required this.documentProgress,
    required this.runOcr,
    required this.cancelOcr,
    required this.ocrProgress,
    required this.mediaStats,
    this.runSemantic,
    this.cancelSemantic,
  });

  static const List<ContentCategory> _mediaCategories = [
    ContentCategory.images,
    ContentCategory.videos,
    ContentCategory.audio,
  ];

  final IndexingMediaSync mediaSync;

  /// Document stage entry points (wired to [DocumentCoordinator]).
  final Future<DocumentRunSummary> Function() runDocuments;
  final void Function() cancelDocuments;
  final Stream<DocumentRunProgress> documentProgress;

  /// OCR stage entry points (wired to [OcrCoordinator]).
  final Future<OcrRunSummary> Function() runOcr;
  final void Function() cancelOcr;
  final Stream<OcrRunProgress> ocrProgress;

  /// Index snapshot taken after synchronization (real totals, never fake).
  final Future<MediaIndexStats> Function() mediaStats;

  /// Semantic embedding stage entry points (wired to [SemanticIndexCoordinator]).
  /// Optional: when null, the semantic stage is skipped entirely and the rest
  /// of the pipeline is unaffected.
  final Stream<SemanticRunProgress> Function()? runSemantic;
  final void Function()? cancelSemantic;

  final StreamController<IndexingStatus> _status =
      StreamController<IndexingStatus>.broadcast();

  /// Latest status across runs — the single UI-visible snapshot.
  Stream<IndexingStatus> get status => _status.stream;

  IndexingStatus? _last;

  /// Last emitted snapshot; null before the first run.
  IndexingStatus? get lastStatus => _last;

  bool _running = false;

  bool get isRunning => _running;

  /// Runs the full pipeline once. Single-flight: a second call while a run is
  /// active returns immediately without queuing a second run.
  Future<IndexingStatus> start() async {
    if (_running) {
      return lastStatus ?? const IndexingStatus.idle();
    }
    _running = true;
    try {
      _emit(const IndexingStatus(phase: IndexingPhase.preparing));

      final syncResult = await mediaSync.run(_mediaCategories);
      final changed = syncResult.units.fold<int>(
        0,
        (sum, unit) => sum + unit.recordsInserted + unit.recordsUpdated,
      );
      switch (syncResult.outcome) {
        case SyncSessionOutcome.cancelled:
          return _finish(await _conclude(IndexingPhase.cancelled));
        case SyncSessionOutcome.failed:
        case SyncSessionOutcome.noAccess:
          return _finish(
            const IndexingStatus(
              phase: IndexingPhase.failed,
              message: 'Media access is unavailable.',
            ),
          );
        case SyncSessionOutcome.completed:
        case SyncSessionOutcome.partialFailure:
          break;
      }

      final stats = await _safeStats();
      _emit(
        IndexingStatus(
          phase: IndexingPhase.persisting,
          mediaIndexed: stats?.total,
          mediaChanged: changed,
        ),
      );

      final concluded = await _enrich();
      return _finish(
        await _conclude(
          concluded ? IndexingPhase.completed : IndexingPhase.cancelled,
        ),
      );
    } catch (_) {
      return _finish(
        const IndexingStatus(
          phase: IndexingPhase.failed,
          message: 'Indexing couldn\'t finish.',
        ),
      );
    } finally {
      _running = false;
    }
  }

  /// Cooperative cancellation of every active stage. The run concludes as
  /// [IndexingPhase.cancelled]; already-persisted work stays valid.
  void cancel() {
    if (!_running) return;
    unawaited(mediaSync.cancel());
    cancelDocuments();
    cancelOcr();
    cancelSemantic?.call();
  }

  /// Drains document extraction, then OCR, then semantic embedding, reporting
  /// live counts. Returns true when all stages concluded without cancellation.
  /// A semantic-stage failure is non-fatal: the run still completes.
  Future<bool> _enrich() async {
    _emit(_rebuild(phase: IndexingPhase.enriching));

    var documentsCancelled = false;
    var documentsFailed = false;
    final docSub = documentProgress.listen((snapshot) {
      _emit(
        _rebuild(
          documentsProcessed: snapshot.processed,
          documentsTotal: snapshot.total,
        ),
      );
    });
    final docSummary = await runDocuments();
    await docSub.cancel();
    documentsCancelled = docSummary.status == DocumentRunStatus.cancelled;
    documentsFailed = docSummary.status == DocumentRunStatus.failed;
    if (documentsFailed) {
      throw StateError('document stage failed');
    }

    if (documentsCancelled) return false;

    var ocrCancelled = false;
    final ocrSub = ocrProgress.listen((snapshot) {
      _emit(
        _rebuild(
          contentProcessed: snapshot.processed,
          contentTotal: snapshot.total,
        ),
      );
    });
    final ocrSummary = await runOcr();
    await ocrSub.cancel();
    ocrCancelled = ocrSummary.status == OcrRunStatus.cancelled;
    if (ocrSummary.status == OcrRunStatus.failed) {
      throw StateError('OCR stage failed');
    }
    if (ocrCancelled) return false;

    // Semantic stage is optional and non-fatal: a failure here does not fail
    // the run, and an unavailable provider simply skips the stage.
    if (runSemantic != null) {
      var semanticCancelled = false;
      final semStream = runSemantic!();
      final completer = Completer<SemanticRunStatus>();
      final sub = semStream.listen((snapshot) {
        _emit(
          _rebuild(
            semanticProcessed: snapshot.processed,
            semanticTotal: snapshot.total,
          ),
        );
        if (snapshot.status == SemanticRunStatus.cancelled ||
            snapshot.status == SemanticRunStatus.completed ||
            snapshot.status == SemanticRunStatus.failed ||
            snapshot.status == SemanticRunStatus.unavailable) {
          completer.complete(snapshot.status);
        }
      });
      final terminalStatus = await completer.future;
      await sub.cancel();
      semanticCancelled = terminalStatus == SemanticRunStatus.cancelled;
      if (semanticCancelled) return false;
      // semantic failed/unavailable is intentionally non-fatal
    }

    return true;
  }

  /// Concludes a run on [phase] without wiping the progress counts the UI
  /// just showed ("N/3,100 analyzed" stays visible until the next run).
  Future<IndexingStatus> _conclude(IndexingPhase phase) async {
    if (phase == IndexingPhase.completed) {
      final stats = await _safeStats();
      return _rebuild(phase: phase, mediaIndexed: stats?.total);
    }
    return _rebuild(phase: phase);
  }

  /// Re-emits on top of the latest snapshot, overriding only given fields.
  IndexingStatus _rebuild({
    IndexingPhase? phase,
    int? mediaIndexed,
    int? mediaChanged,
    int? contentProcessed,
    int? contentTotal,
    int? documentsProcessed,
    int? documentsTotal,
    int? semanticProcessed,
    int? semanticTotal,
  }) {
    final current = _last ?? const IndexingStatus.idle();
    return IndexingStatus(
      phase: phase ?? current.phase,
      mediaIndexed: mediaIndexed ?? current.mediaIndexed,
      mediaChanged: mediaChanged ?? current.mediaChanged,
      contentProcessed: contentProcessed ?? current.contentProcessed,
      contentTotal: contentTotal ?? current.contentTotal,
      documentsProcessed: documentsProcessed ?? current.documentsProcessed,
      documentsTotal: documentsTotal ?? current.documentsTotal,
      semanticProcessed: semanticProcessed ?? current.semanticProcessed,
      semanticTotal: semanticTotal ?? current.semanticTotal,
      message: current.message,
    );
  }

  Future<MediaIndexStats?> _safeStats() async {
    try {
      return await mediaStats();
    } catch (_) {
      return null;
    }
  }

  IndexingStatus _finish(IndexingStatus status) {
    _emit(status);
    return status;
  }

  void _emit(IndexingStatus status) {
    _last = status;
    _status.add(status);
  }
}
