import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_item_mapper.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/database/discovery_persistence_orchestrator.dart';
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart';

import 'media_repository_test.dart' show ThrowingBatchMapper;
import 'test_support.dart';

void main() {
  group('DiscoveryPersistenceOrchestrator', () {
    late AppDatabase db;

    setUp(() {
      db = inMemoryDb();
    });

    tearDown(() async {
      await db.close();
    });

    MediaRepository repositoryWith({MediaItemMapper? mapper}) =>
        DriftMediaRepository(db, mapper: mapper ?? const MediaItemMapper());

    DiscoveryPersistenceOrchestrator orchestrator(MediaItemMapper? mapper) =>
        DiscoveryPersistenceOrchestrator(
          repository: repositoryWith(mapper: mapper),
        );

    test('persists each batch before acknowledging it', () async {
      final acked = <int>[];
      final summary = await orchestrator(null).run(
        events: Stream.fromIterable([
          buildBatch(
            sequence: 1,
            records: [buildRecord(id: 1), buildRecord(id: 2)],
            hasMore: true,
          ),
          buildBatch(
            sequence: 2,
            records: [buildRecord(id: 3)],
            hasMore: false,
          ),
          DiscoveryCompletedEvent(
            recordsDiscovered: 3,
            skippedRecords: 0,
            batchesSent: 2,
            categories: [ContentCategory.images],
            volumes: ['external_primary'],
          ),
        ]),
        ackBatch: (sequence) async {
          acked.add(sequence);
          return true;
        },
      );

      expect(summary.state, DiscoveryLifecycleState.completed);
      expect(summary.batchesPersisted, 2);
      expect(summary.recordsPersisted, 3);
      expect(summary.errorCode, isNull);
      expect(acked, [1, 2]);
      expect(await repositoryWith().count(), 3);
    });

    test(
      'acknowledges the terminal batch and still completes cleanly',
      () async {
        final acked = <int>[];
        final summary = await orchestrator(null).run(
          events: Stream.fromIterable([
            buildBatch(sequence: 5, records: [buildRecord(id: 7)]),
            DiscoveryCompletedEvent(
              recordsDiscovered: 1,
              skippedRecords: 0,
              batchesSent: 1,
              categories: [ContentCategory.images],
              volumes: ['external_primary'],
            ),
          ]),
          ackBatch: (sequence) async {
            acked.add(sequence);
            return true;
          },
        );

        expect(summary.state, DiscoveryLifecycleState.completed);
        expect(acked, [5]);
      },
    );

    test(
      'acknowledges already-committed batches when a run is cancelled',
      () async {
        final acked = <int>[];
        final summary = await orchestrator(null).run(
          events: Stream.fromIterable([
            buildBatch(sequence: 1, records: [buildRecord(id: 1)]),
            buildBatch(sequence: 2, records: [buildRecord(id: 2)]),
            DiscoveryCancelledEvent(
              recordsDiscovered: 2,
              skippedRecords: 0,
              batchesSent: 2,
            ),
          ]),
          ackBatch: (sequence) async {
            acked.add(sequence);
            return true;
          },
        );

        expect(summary.state, DiscoveryLifecycleState.cancelled);
        expect(summary.batchesPersisted, 2);
        expect(acked, [1, 2]);
        expect(await repositoryWith().count(), 2);
      },
    );

    test('surfaces the scanner error after persisting prior batches', () async {
      final summary = await orchestrator(null).run(
        events: Stream.fromIterable([
          buildBatch(sequence: 1, records: [buildRecord(id: 1)]),
          const DiscoveryErrorEvent(
            code: 'permissionDenied',
            message: 'Media permission was revoked',
          ),
        ]),
        ackBatch: (_) async => true,
      );

      expect(summary.state, DiscoveryLifecycleState.failed);
      expect(summary.errorCode, 'permissionDenied');
      expect(summary.errorMessage, 'Media permission was revoked');
      expect(summary.failedBatchSequence, isNull);
      expect(await repositoryWith().count(), 1);
    });

    test(
      'does not acknowledge a batch whose ACK the scanner rejects',
      () async {
        final acked = <int>[];
        final summary = await orchestrator(null).run(
          events: Stream.fromIterable([
            buildBatch(sequence: 3, records: [buildRecord(id: 1)]),
          ]),
          ackBatch: (sequence) async {
            acked.add(sequence);
            return false;
          },
        );

        expect(summary.state, DiscoveryLifecycleState.failed);
        expect(summary.errorCode, 'ackRejected');
        expect(summary.failedBatchSequence, 3);
        // The data was committed, but the session failed loudly.
        expect(await repositoryWith().count(), 1);
      },
    );

    test(
      'never ACKs a batch that failed to persist and rolls it back',
      () async {
        final acked = <int>[];
        final summary =
            await orchestrator(const ThrowingBatchMapper('external_primary:2'))
                .run(
                  events: Stream.fromIterable([
                    buildBatch(
                      sequence: 4,
                      records: [buildRecord(id: 1), buildRecord(id: 2)],
                    ),
                  ]),
                  ackBatch: (sequence) async {
                    acked.add(sequence);
                    return true;
                  },
                );

        expect(summary.state, DiscoveryLifecycleState.failed);
        expect(summary.errorCode, 'persistenceFailed');
        expect(summary.failedBatchSequence, 4);
        expect(acked, isEmpty);
        // The batch transaction rolled back — no partial rows.
        expect(await repositoryWith().count(), 0);
      },
    );

    test(
      'marks a run interrupted when the stream ends without a terminal event',
      () async {
        final summary = await orchestrator(null).run(
          events: Stream.fromIterable([
            buildBatch(sequence: 1, records: [buildRecord(id: 1)]),
          ]),
          ackBatch: (_) async => true,
        );

        expect(summary.state, DiscoveryLifecycleState.failed);
        expect(summary.errorCode, 'discoveryInterrupted');
        expect(summary.batchesPersisted, 1);
      },
    );

    test('marks a run failed when the stream errors', () async {
      final controller = StreamController<DiscoveryEvent>();
      final future = orchestrator(null)
          .run(events: controller.stream, ackBatch: (_) async => true);

      controller.addError(Exception('stream exploded'));
      controller.close();

      final summary = await future;
      expect(summary.state, DiscoveryLifecycleState.failed);
      expect(summary.errorCode, 'discoveryStreamError');
    });

    test(
      'an exception thrown by the ACK itself fails the run loudly',
      () async {
        final summary = await orchestrator(null).run(
          events: Stream.fromIterable([
            buildBatch(sequence: 1, records: [buildRecord(id: 1)]),
          ]),
          ackBatch: (_) async => throw StateError('ack transport gone'),
        );

        // The write already committed; only the ACK failed.
        expect(await repositoryWith().count(), 1);
        expect(summary.state, DiscoveryLifecycleState.failed);
        expect(summary.errorCode, 'persistenceFailed');
        expect(summary.failedBatchSequence, 1);
      },
    );
  });
}
