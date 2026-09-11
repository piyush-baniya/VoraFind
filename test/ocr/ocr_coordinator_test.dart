import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/ocr/ocr_coordinator.dart';
import 'package:vorafind/core/ocr/ocr_detector.dart';
import 'package:vorafind/core/ocr/ocr_models.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart'
    show DiscoveryAccessScope;

import '../database/test_support.dart';

/// Detector whose outcome per content URI is either a `String` (success) or an
/// [OcrRecognitionException] (failure). [waitFor] can gate the call at index
/// [i] so tests can cancel mid-run deterministically.
class RecordingDetector implements OcrDetector {
  RecordingDetector(this.outcomes, {this.waitFor});

  final Map<String, Object> outcomes;
  final Future<void> Function(int callIndex)? waitFor;
  final contentUris = <String>[];
  final maxWidths = <int?>[];
  int callCount = 0;

  @override
  Future<OcrRecognitionResult> recognizeText(
    String contentUri, {
    int? maxWidth,
  }) async {
    final index = callCount++;
    contentUris.add(contentUri);
    maxWidths.add(maxWidth);
    await waitFor?.call(index);
    final outcome = outcomes[contentUri]!;
    if (outcome is OcrRecognitionException) throw outcome;
    return OcrRecognitionResult(text: outcome as String);
  }
}

void main() {
  group('OcrCoordinator', () {
    late AppDatabase db;
    late DriftMediaRepository repository;

    setUp(() {
      db = inMemoryDb();
      repository = DriftMediaRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seedImage(int id, {String? displayName}) => repository.upsert(
      buildRecord(id: id, displayName: displayName),
      accessScope: DiscoveryAccessScope.full,
    );

    String uri(int id) => 'content://media/external_primary/images/media/$id';

    Future<void> pumpFrames([int count = 20]) async {
      for (var i = 0; i < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    OcrCoordinator coordinator(OcrDetector detector, {int batchSize = 10}) =>
        OcrCoordinator(
          repository: repository,
          detector: detector,
          batchSize: batchSize,
          nowSeconds: () => 1000,
        );

    test(
      'drains the pending queue to a completed run with correct counts',
      () async {
        await seedImage(1);
        await seedImage(2, displayName: 'IMG_2.jpg');
        final detector = RecordingDetector({
          uri(1): 'aadhaar card',
          uri(2): 'hospital receipt',
        });

        final summary = await coordinator(detector).start();

        expect(summary.status, OcrRunStatus.completed);
        expect(summary.processed, 2);
        expect(summary.succeeded, 2);
        expect(summary.failed, 0);
        expect(detector.contentUris, unorderedEquals([uri(1), uri(2)]));
        expect(detector.maxWidths, everyElement(2048));

        final first = await repository.getOcrStatus('external_primary:1');
        expect(first!.status, OcrStatus.completed);
        expect(first.sourceRevision, 1);
      },
    );

    test(
      'an empty queue completes immediately without touching the detector',
      () async {
        final detector = RecordingDetector(<String, Object>{});

        final summary = await coordinator(detector).start();

        expect(summary.status, OcrRunStatus.completed);
        expect(summary.processed, 0);
        expect(summary.succeeded, 0);
        expect(detector.callCount, 0);
      },
    );

    test('per-row failures are isolated: transient -> failed, undecodable -> '
        'unsupported, never failing the run', () async {
      await seedImage(1); // transient (uri gone)
      await seedImage(2); // undecodable bytes (permanent)
      await seedImage(3); // recognizer hiccup (transient)
      await seedImage(4); // success
      final detector = RecordingDetector({
        uri(1): const OcrRecognitionException(
          code: OcrErrorCode.uriUnavailable,
        ),
        uri(2): const OcrRecognitionException(code: OcrErrorCode.decodeFailed),
        uri(3): const OcrRecognitionException(code: OcrErrorCode.ocrFailed),
        uri(4): 'the good one',
      });

      final summary = await coordinator(detector).start();

      expect(summary.status, OcrRunStatus.completed);
      expect(summary.processed, 4);
      expect(summary.succeeded, 1);
      expect(summary.failed, 3);

      final first = await repository.getOcrStatus('external_primary:1');
      expect(first!.status, OcrStatus.failed);
      expect(first.errorCode, OcrErrorCode.uriUnavailable.name);
      final second = await repository.getOcrStatus('external_primary:2');
      expect(second!.status, OcrStatus.unsupported);
      expect(second.errorCode, OcrErrorCode.decodeFailed.name);
      final third = await repository.getOcrStatus('external_primary:3');
      expect(third!.status, OcrStatus.failed);
      final fourth = await repository.getOcrStatus('external_primary:4');
      expect(fourth!.status, OcrStatus.completed);
    });

    test('cancellation stops the run at the next candidate boundary', () async {
      await seedImage(1);
      await seedImage(2);
      final gate = Completer<void>();
      final detector = RecordingDetector(
        {uri(1): 'in flight', uri(2): 'queued but cancelled'},
        waitFor: (index) async {
          if (index == 0) await gate.future;
        },
      );

      final ocr = coordinator(detector);
      final run = ocr.start();
      // Spin until the first candidate is actually being recognized.
      while (detector.callCount == 0) {
        await pumpFrames();
      }
      expect(ocr.isRunning, isTrue);

      ocr.cancel();
      gate.complete();
      final summary = await run;

      expect(summary.status, OcrRunStatus.cancelled);
      expect(summary.processed, 1);
      expect(summary.succeeded, 1);
      // The second candidate was never touched.
      expect(detector.contentUris, [uri(1)]);
      expect(await repository.getOcrStatus('external_primary:2'), isNull);
    });

    test(
      'starting while a run is active does not queue a second run',
      () async {
        await seedImage(1);
        await seedImage(2);
        final gate = Completer<void>();
        final detector = RecordingDetector(
          {uri(1): 'one', uri(2): 'two'},
          waitFor: (index) async {
            if (index == 0) await gate.future;
          },
        );

        final ocr = coordinator(detector);
        final first = ocr.start();
        final second = ocr.start();

        expect((await second).status, OcrRunStatus.running);
        gate.complete();
        final summary = await first;
        expect(summary.status, OcrRunStatus.completed);
        expect(detector.callCount, 2);
      },
    );

    test('progress stream emits running then a terminal snapshot', () async {
      await seedImage(1);
      final detector = RecordingDetector({uri(1): 'progress text'});
      final snapshots = <OcrRunProgress>[];
      final ocr = coordinator(detector);
      ocr.progress.listen(snapshots.add);

      await ocr.start();
      // Broadcast-stream fan-out runs on microtasks after `start()` awaits.
      await Future<void>.delayed(Duration.zero);

      expect(snapshots.first.status, OcrRunStatus.running);
      expect(snapshots.last.status, OcrRunStatus.completed);
      expect(snapshots.length, greaterThanOrEqualTo(2));
      expect(snapshots.first.total, 1);
      expect(snapshots.last.processed, 1);
    });
  });
}
