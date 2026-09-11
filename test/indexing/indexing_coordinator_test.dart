import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/media_repository.dart'
    show MediaIndexStats;
import 'package:vorafind/core/database/synchronization_coordinator.dart';
import 'package:vorafind/core/documents/document_coordinator.dart';
import 'package:vorafind/core/documents/document_models.dart'
    show DocumentRunStatus;
import 'package:vorafind/core/indexing/indexing_coordinator.dart';
import 'package:vorafind/core/ocr/ocr_coordinator.dart';
import 'package:vorafind/core/ocr/ocr_models.dart' show OcrRunStatus;
import 'package:vorafind/core/platform/content_access_models.dart';

/// Configurable media-sync stage that records cancellation requests.
class FakeMediaSync implements IndexingMediaSync {
  FakeMediaSync({this.result});

  SyncSessionResult? result;
  int cancelCount = 0;
  int runCount = 0;

  Completer<void>? gate;

  @override
  Future<SyncSessionResult> run(List<ContentCategory> categories) async {
    runCount++;
    await gate?.future;
    return result!;
  }

  @override
  Future<void> cancel() async => cancelCount++;
}

SyncSessionResult _syncResult(SyncSessionOutcome outcome) => SyncSessionResult(
  outcome: outcome,
  units: [
    SyncUnitResult(
      category: ContentCategory.images,
      volumeName: 'external_primary',
      kind: SyncUnitKind.firstIndex,
      recordsInserted: 12,
      recordsUpdated: 3,
    ),
  ],
);

DocumentRunProgress _docSnapshot(int processed, int total) =>
    DocumentRunProgress(
      status: DocumentRunStatus.running,
      processed: processed,
      total: total,
      succeeded: processed,
      failed: 0,
    );

OcrRunProgress _ocrSnapshot(int processed, int total) => OcrRunProgress(
  status: OcrRunStatus.running,
  processed: processed,
  total: total,
  succeeded: processed,
  failed: 0,
);

IndexingCoordinator _coordinator({
  required FakeMediaSync sync,
  required DocumentRunSummary documentSummary,
  required OcrRunSummary ocrSummary,
  List<DocumentRunProgress> docSnapshots = const [],
  List<OcrRunProgress> ocrSnapshots = const [],
}) {
  final docController = StreamController<DocumentRunProgress>.broadcast(
    sync: true,
  );
  final ocrController = StreamController<OcrRunProgress>.broadcast(sync: true);
  return IndexingCoordinator(
    mediaSync: sync,
    runDocuments: () async {
      for (final snapshot in docSnapshots) {
        docController.add(snapshot);
      }
      return documentSummary;
    },
    cancelDocuments: () {},
    documentProgress: docController.stream,
    runOcr: () async {
      for (final snapshot in ocrSnapshots) {
        ocrController.add(snapshot);
      }
      return ocrSummary;
    },
    cancelOcr: () {},
    ocrProgress: ocrController.stream,
    mediaStats: () async =>
        const MediaIndexStats(total: 42, byCategory: {}, volumeCount: 1),
  );
}

void main() {
  group('IndexingCoordinator', () {
    test(
      'happy path: preparing → persisting → enriching → completed',
      () async {
        final sync = FakeMediaSync(
          result: _syncResult(SyncSessionOutcome.completed),
        );
        final snapshots = <IndexingStatus>[];
        final coordinator = _coordinator(
          sync: sync,
          documentSummary: const DocumentRunSummary(
            status: DocumentRunStatus.completed,
            processed: 5,
            succeeded: 5,
          ),
          ocrSummary: const OcrRunSummary(
            status: OcrRunStatus.completed,
            processed: 9,
            succeeded: 9,
          ),
          docSnapshots: [_docSnapshot(2, 5)],
          ocrSnapshots: [_ocrSnapshot(4, 9)],
        );
        coordinator.status.listen(snapshots.add);

        final outcome = await coordinator.start();

        expect(outcome.phase, IndexingPhase.completed);
        expect(outcome.mediaIndexed, 42);
        expect(outcome.documentsProcessed, 2);
        expect(outcome.documentsTotal, 5);
        expect(outcome.contentProcessed, 4);
        expect(outcome.contentTotal, 9);
        expect(sync.runCount, 1);
        expect(snapshots.first.phase, IndexingPhase.preparing);
        expect(
          snapshots.any((s) => s.phase == IndexingPhase.persisting),
          isTrue,
        );
        // Status deliveries are queued microtasks; flush the event loop so
        // the terminal snapshot reaches the listener before we assert.
        await Future<void>.delayed(Duration.zero);
        expect(snapshots.last.phase, IndexingPhase.completed);
        expect(snapshots.last.mediaIndexed, 42);
        expect(snapshots.last.mediaIndexed, 42);
      },
    );

    test('enrichment progress keeps the media total visible', () async {
      final sync = FakeMediaSync(
        result: _syncResult(SyncSessionOutcome.completed),
      );
      final coordinator = _coordinator(
        sync: sync,
        documentSummary: const DocumentRunSummary(
          status: DocumentRunStatus.completed,
        ),
        ocrSummary: const OcrRunSummary(status: OcrRunStatus.completed),
        ocrSnapshots: [_ocrSnapshot(3, 9)],
      );

      final outcome = await coordinator.start();

      expect(outcome.phase, IndexingPhase.completed);
      expect(outcome.mediaIndexed, 42);
      expect(outcome.contentProcessed, 3);
      expect(outcome.contentTotal, 9);
    });

    test('sync failure fails the run without touching enrichment', () async {
      final sync = FakeMediaSync(
        result: _syncResult(SyncSessionOutcome.failed),
      );
      var documentsCalled = false;
      final coordinator = IndexingCoordinator(
        mediaSync: sync,
        runDocuments: () async {
          documentsCalled = true;
          return const DocumentRunSummary(status: DocumentRunStatus.completed);
        },
        cancelDocuments: () {},
        documentProgress: const Stream<DocumentRunProgress>.empty(),
        runOcr: () async => const OcrRunSummary(status: OcrRunStatus.completed),
        cancelOcr: () {},
        ocrProgress: const Stream<OcrRunProgress>.empty(),
        mediaStats: () async =>
            const MediaIndexStats(total: 0, byCategory: {}, volumeCount: 0),
      );

      final outcome = await coordinator.start();

      expect(outcome.phase, IndexingPhase.failed);
      expect(outcome.message, isNotNull);
      expect(documentsCalled, isFalse);
    });

    test('cancelled sync concludes as cancelled without enrichment', () async {
      var documentsCalled = false;
      final coordinator = IndexingCoordinator(
        mediaSync: FakeMediaSync(
          result: _syncResult(SyncSessionOutcome.cancelled),
        ),
        runDocuments: () async {
          documentsCalled = true;
          return const DocumentRunSummary(status: DocumentRunStatus.completed);
        },
        cancelDocuments: () {},
        documentProgress: const Stream<DocumentRunProgress>.empty(),
        runOcr: () async => const OcrRunSummary(status: OcrRunStatus.completed),
        cancelOcr: () {},
        ocrProgress: const Stream<OcrRunProgress>.empty(),
        mediaStats: () async =>
            const MediaIndexStats(total: 0, byCategory: {}, volumeCount: 0),
      );

      final outcome = await coordinator.start();

      expect(outcome.phase, IndexingPhase.cancelled);
      expect(documentsCalled, isFalse);
    });

    test('document cancellation skips OCR and concludes cancelled', () async {
      var ocrCalled = false;
      final probe = IndexingCoordinator(
        mediaSync: FakeMediaSync(
          result: _syncResult(SyncSessionOutcome.completed),
        ),
        runDocuments: () async => const DocumentRunSummary(
          status: DocumentRunStatus.cancelled,
          processed: 2,
        ),
        cancelDocuments: () {},
        documentProgress: const Stream<DocumentRunProgress>.empty(),
        runOcr: () async {
          ocrCalled = true;
          return const OcrRunSummary(status: OcrRunStatus.completed);
        },
        cancelOcr: () {},
        ocrProgress: const Stream<OcrRunProgress>.empty(),
        mediaStats: () async =>
            const MediaIndexStats(total: 1, byCategory: {}, volumeCount: 1),
      );

      final outcome = await probe.start();

      expect(outcome.phase, IndexingPhase.cancelled);
      expect(ocrCalled, isFalse);
    });

    test('document stage failure fails the run without touching OCR', () async {
      var ocrCalled = false;
      final probe = IndexingCoordinator(
        mediaSync: FakeMediaSync(
          result: _syncResult(SyncSessionOutcome.completed),
        ),
        runDocuments: () async {
          throw StateError('document stage failed');
        },
        cancelDocuments: () {},
        documentProgress: const Stream<DocumentRunProgress>.empty(),
        runOcr: () async {
          ocrCalled = true;
          return const OcrRunSummary(status: OcrRunStatus.completed);
        },
        cancelOcr: () {},
        ocrProgress: const Stream<OcrRunProgress>.empty(),
        mediaStats: () async =>
            const MediaIndexStats(total: 1, byCategory: {}, volumeCount: 1),
      );

      final outcome = await probe.start();

      expect(outcome.phase, IndexingPhase.failed);
      expect(ocrCalled, isFalse);
    });
    test(
      'OCR cancellation concludes cancelled with preserved counts',
      () async {
        final coordinator = _coordinator(
          sync: FakeMediaSync(
            result: _syncResult(SyncSessionOutcome.completed),
          ),
          documentSummary: const DocumentRunSummary(
            status: DocumentRunStatus.completed,
            processed: 5,
            succeeded: 5,
          ),
          ocrSummary: const OcrRunSummary(
            status: OcrRunStatus.cancelled,
            processed: 4,
            succeeded: 4,
          ),
          docSnapshots: [_docSnapshot(5, 5)],
          ocrSnapshots: [_ocrSnapshot(4, 20)],
        );

        final outcome = await coordinator.start();

        expect(outcome.phase, IndexingPhase.cancelled);
        expect(outcome.documentsProcessed, 5);
        expect(outcome.contentProcessed, 4);
        expect(outcome.contentTotal, 20);
      },
    );

    test(
      'starting while a run is active does not queue a second run',
      () async {
        final sync = FakeMediaSync(
          result: _syncResult(SyncSessionOutcome.completed),
        )..gate = Completer<void>();
        final coordinator = _coordinator(
          sync: sync,
          documentSummary: const DocumentRunSummary(
            status: DocumentRunStatus.completed,
          ),
          ocrSummary: const OcrRunSummary(status: OcrRunStatus.completed),
        );

        final first = coordinator.start();
        // Single-flight: the second call reports the current snapshot
        // (preparing — the sync gate is not released yet), never queues.
        final second = await coordinator.start();
        sync.gate!.complete();
        await first;

        expect(second.phase, IndexingPhase.preparing);
        expect(sync.runCount, 1);
      },
    );

    test('cancel requests cancellation on every active stage', () async {
      final sync = FakeMediaSync(
        result: _syncResult(SyncSessionOutcome.completed),
      )..gate = Completer<void>();
      var ocrCancelCount = 0;
      final coordinator = IndexingCoordinator(
        mediaSync: sync,
        runDocuments: () async =>
            const DocumentRunSummary(status: DocumentRunStatus.completed),
        cancelDocuments: () {},
        documentProgress: const Stream<DocumentRunProgress>.empty(),
        runOcr: () async => const OcrRunSummary(status: OcrRunStatus.completed),
        cancelOcr: () => ocrCancelCount++,
        ocrProgress: const Stream<OcrRunProgress>.empty(),
        mediaStats: () async =>
            const MediaIndexStats(total: 1, byCategory: {}, volumeCount: 1),
      );

      final run = coordinator.start();
      coordinator.cancel();
      sync.gate!.complete();
      await run;

      expect(sync.cancelCount, 1);
      expect(ocrCancelCount, 1);
    });
  });
}
