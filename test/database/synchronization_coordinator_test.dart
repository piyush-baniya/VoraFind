import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/database/synchronization_coordinator.dart';
import 'package:vorafind/core/platform/content_access.dart';
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/platform/media_discovery.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart';

import 'test_support.dart';

/// One scan unit a script plays back: a category/volume walk with batches.
class ScriptUnit {
  ScriptUnit({
    required this.category,
    required this.volume,
    this.scope = DiscoveryAccessScope.full,
    this.batches = const [],
    this.error = false,
    this.cancel = false,
  });

  final ContentCategory category;
  final String volume;
  final DiscoveryAccessScope scope;

  /// (records, hasMore, generationAfter)
  final List<(List<MediaDiscoveryRecord>, bool, int?)> batches;
  final bool error;
  final bool cancel;
}

/// Builds the full ordered event list for one discovery session from units.
List<DiscoveryEvent> buildScript(List<ScriptUnit> units) {
  final events = <DiscoveryEvent>[];
  var sequence = 1;
  var terminal = false;
  for (final unit in units) {
    events.add(
      DiscoveryStartedEvent(
        category: unit.category,
        volume: unit.volume,
        accessScope: unit.scope,
      ),
    );
    for (final (records, hasMore, generationAfter) in unit.batches) {
      events.add(
        DiscoveryBatchEvent(
          sequence: sequence,
          category: unit.category,
          volume: unit.volume,
          accessScope: unit.scope,
          records: records,
          hasMore: hasMore,
          skippedCount: 0,
          generationAfter: generationAfter,
        ),
      );
      sequence += 1;
    }
    if (unit.error) {
      events.add(
        const DiscoveryErrorEvent(
          code: 'scanFailed',
          message: 'volume scan failed mid-way',
        ),
      );
      terminal = true;
      break;
    }
    if (unit.cancel) {
      events.add(
        DiscoveryCancelledEvent(
          recordsDiscovered: 0,
          skippedRecords: 0,
          batchesSent: sequence,
        ),
      );
      terminal = true;
      break;
    }
  }
  if (!terminal) {
    events.add(
      DiscoveryCompletedEvent(
        recordsDiscovered: 0,
        skippedRecords: 0,
        batchesSent: sequence,
        categories: [for (final unit in units) unit.category],
        volumes: [for (final unit in units) unit.volume],
      ),
    );
  }
  return events;
}

class FakeDiscovery implements MediaDiscovery {
  final StreamController<DiscoveryEvent> eventsController =
      StreamController.broadcast();

  final List<List<ContentCategory>> startedCategories = [];
  final List<List<String>> volumeFilters = [];
  final Map<({ContentCategory category, String volume}), int?> generations = {};
  final List<int> acked = [];
  int cancelCalls = 0;
  bool refuseStart = false;
  String refuseCode = 'discoveryStartFailed';
  final List<List<DiscoveryEvent>> scripts = [];

  void generation(ContentCategory category, String volume, int? value) {
    generations[(category: category, volume: volume)] = value;
  }

  void play(List<DiscoveryEvent> events) => scripts.add(events);

  @override
  Stream<DiscoveryEvent> events() => eventsController.stream;

  @override
  Future<DiscoveryStartResult> startDiscovery(
    List<ContentCategory> categories, {
    List<String>? volumes,
  }) async {
    startedCategories.add(List.of(categories));
    volumeFilters.add(List.of(volumes ?? const []));
    if (refuseStart) {
      return DiscoveryStartResult(
        accepted: false,
        contractVersion: 1,
        code: refuseCode,
        categories: const [],
      );
    }
    if (scripts.isNotEmpty) {
      for (final event in scripts.removeAt(0)) {
        eventsController.add(event);
      }
    }
    return DiscoveryStartResult(
      accepted: true,
      contractVersion: 1,
      code: null,
      categories: [
        for (final category in categories)
          StartCategoryStatus(
            category: category,
            status: CategoryStartStatus.started,
            accessScope: DiscoveryAccessScope.full,
          ),
      ],
    );
  }

  @override
  Future<int?> getGeneration(
    ContentCategory category,
    String volumeName,
  ) async {
    return generations[(category: category, volume: volumeName)];
  }

  @override
  Future<bool> ackBatch(int sequence) async {
    acked.add(sequence);
    return true;
  }

  @override
  Future<bool> cancelDiscovery() async {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<DiscoveryStatus> getDiscoveryStatus() async => DiscoveryStatus(
    state: DiscoveryLifecycleState.idle,
    currentCategory: null,
    currentVolume: null,
    sequence: 0,
    batchesSent: 0,
    recordsDiscovered: 0,
    skippedRecords: 0,
    lastError: null,
  );
}

class FakeContentAccess implements ContentAccess {
  FakeContentAccess({required this.volumes, required this.states});

  final List<String> volumes;
  final Map<ContentCategory, ContentAccessState> states;

  @override
  Future<ContentCapabilities> getCapabilities() async => ContentCapabilities(
    contractVersion: 1,
    apiLevel: 33,
    safCapable: false,
    mediaStoreGenerationSupported: true,
    partialMediaAccessSupported: true,
    externalVolumes: volumes,
    categories: [
      for (final entry in states.entries)
        ContentCategoryAccess(category: entry.key, state: entry.value),
    ],
  );

  @override
  Future<ContentCategoryAccess> getPermissionState(ContentCategory category) =>
      throw UnimplementedError();

  @override
  Future<ContentCategoryAccess> requestMediaAccess(ContentCategory category) =>
      throw UnimplementedError();

  @override
  Future<DocumentGrantResult> requestDocumentTree() =>
      throw UnimplementedError();

  @override
  Future<List<DocumentGrant>> listDocumentTreeGrants() =>
      throw UnimplementedError();

  @override
  Future<bool> releaseDocumentTreeGrant(String uri) =>
      throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late DriftMediaRepository repository;
  late FakeDiscovery discovery;
  late FakeContentAccess access;

  SynchronizationCoordinator coordinator() => SynchronizationCoordinator(
    repository: repository,
    discovery: discovery,
    contentAccess: access,
    nowSeconds: () => 12345,
  );

  Future<SyncSessionResult> run(List<ContentCategory> categories) =>
      coordinator().run(categories);

  setUp(() {
    db = inMemoryDb();
    repository = DriftMediaRepository(db);
    discovery = FakeDiscovery();
    access = FakeContentAccess(
      volumes: const ['external_primary'],
      states: const {ContentCategory.images: ContentAccessState.fullAccess},
    );
  });

  tearDown(() async {
    await discovery.eventsController.close();
    await db.close();
  });

  Future<void> seedRows(int first, int last) async {
    for (var id = first; id <= last; id++) {
      await repository.upsert(buildRecord(id: id));
    }
  }

  Future<void> seedCheckpoint({
    ContentCategory category = ContentCategory.images,
    String volume = 'external_primary',
    int? generation = 100,
    DiscoveryAccessScope scope = DiscoveryAccessScope.full,
    String result = 'firstIndex',
  }) async {
    await repository.saveSyncCheckpoint(
      SyncCheckpoint(
        category: category,
        volumeName: volume,
        lastGeneration: generation,
        lastAccessScope: scope,
        lastSyncAt: 999,
        lastResult: result,
      ),
    );
  }

  group('SynchronizationCoordinator', () {
    test('runs an empty request immediately', () async {
      final result = await run(const []);
      expect(result.outcome, SyncSessionOutcome.completed);
      expect(result.units, isEmpty);
      expect(discovery.startedCategories, isEmpty);
    });

    test('first index scan creates rows, checkpoint, and result', () async {
      discovery.generation(ContentCategory.images, 'external_primary', 100);
      discovery.play(
        buildScript([
          ScriptUnit(
            category: ContentCategory.images,
            volume: 'external_primary',
            batches: [
              (
                [buildRecord(id: 1), buildRecord(id: 2), buildRecord(id: 3)],
                false,
                100,
              ),
            ],
          ),
        ]),
      );

      final result = await run(const [ContentCategory.images]);

      expect(result.outcome, SyncSessionOutcome.completed);
      expect(result.units, hasLength(1));
      final unit = result.units.single;
      expect(unit.kind, SyncUnitKind.firstIndex);
      expect(unit.recordsInserted, 3);
      expect(unit.recordsDeleted, 0);
      expect(unit.checkpointAdvanced, isTrue);
      expect(await repository.count(), 3);

      final checkpoint = await repository.getSyncCheckpoint(
        ContentCategory.images,
        'external_primary',
      );
      expect(checkpoint!.lastGeneration, 100);
      expect(checkpoint.lastAccessScope, DiscoveryAccessScope.full);
      expect(checkpoint.lastResult, SyncUnitKind.firstIndex.name);
      expect(checkpoint.lastSyncAt, 12345);
    });

    test('unchanged fast-check skips scanning entirely', () async {
      await seedRows(1, 2);
      await seedCheckpoint();
      discovery.generation(ContentCategory.images, 'external_primary', 100);

      final result = await run(const [ContentCategory.images]);

      expect(result.outcome, SyncSessionOutcome.completed);
      expect(result.units.single.kind, SyncUnitKind.unchanged);
      expect(
        discovery.startedCategories,
        isEmpty,
        reason: 'a matching generation must not trigger a scan',
      );
      expect(await repository.count(), 2);
    });

    test(
      'full-scope rescan reconciles deletions after a generation change',
      () async {
        await seedRows(1, 5);
        await seedCheckpoint();
        discovery.generation(ContentCategory.images, 'external_primary', 200);
        discovery.play(
          buildScript([
            ScriptUnit(
              category: ContentCategory.images,
              volume: 'external_primary',
              batches: [
                (
                  [buildRecord(id: 1), buildRecord(id: 2), buildRecord(id: 3)],
                  false,
                  200,
                ),
              ],
            ),
          ]),
        );

        final result = await run(const [ContentCategory.images]);

        expect(result.outcome, SyncSessionOutcome.completed);
        final unit = result.units.single;
        expect(unit.kind, SyncUnitKind.reconciled);
        expect(unit.recordsDeleted, 2);
        expect(await repository.count(), 3);
        final checkpoint = await repository.getSyncCheckpoint(
          ContentCategory.images,
          'external_primary',
        );
        expect(checkpoint!.lastGeneration, 200);
      },
    );

    test('partial access adds/updates but never deletes', () async {
      access = FakeContentAccess(
        volumes: const ['external_primary'],
        states: const {
          ContentCategory.images: ContentAccessState.partialAccess,
        },
      );
      await seedRows(1, 3);
      await seedCheckpoint();
      discovery.generation(ContentCategory.images, 'external_primary', 200);
      discovery.play(
        buildScript([
          ScriptUnit(
            category: ContentCategory.images,
            volume: 'external_primary',
            scope: DiscoveryAccessScope.partial,
            batches: [
              ([buildRecord(id: 1), buildRecord(id: 2)], false, 200),
            ],
          ),
        ]),
      );

      final result = await run(const [ContentCategory.images]);

      expect(result.outcome, SyncSessionOutcome.completed);
      expect(result.units.single.kind, SyncUnitKind.partialAccess);
      expect(
        await repository.count(),
        3,
        reason: 'row 3 is missing from the partial scan and must be kept',
      );
      final checkpoint = await repository.getSyncCheckpoint(
        ContentCategory.images,
        'external_primary',
      );
      expect(checkpoint!.lastAccessScope, DiscoveryAccessScope.partial);
    });

    test('partial-to-full upgrade allows full reconciliation', () async {
      await seedRows(1, 3);
      await seedCheckpoint(
        scope: DiscoveryAccessScope.partial,
        result: SyncUnitKind.partialAccess.name,
      );
      discovery.generation(ContentCategory.images, 'external_primary', 200);
      discovery.play(
        buildScript([
          ScriptUnit(
            category: ContentCategory.images,
            volume: 'external_primary',
            batches: [
              ([buildRecord(id: 1), buildRecord(id: 2)], false, 200),
            ],
          ),
        ]),
      );

      final result = await run(const [ContentCategory.images]);

      expect(result.outcome, SyncSessionOutcome.completed);
      expect(result.units.single.kind, SyncUnitKind.reconciled);
      expect(await repository.count(), 2);
      final checkpoint = await repository.getSyncCheckpoint(
        ContentCategory.images,
        'external_primary',
      );
      expect(checkpoint!.lastAccessScope, DiscoveryAccessScope.full);
    });

    test(
      'one failing unit makes a partial failure but keeps the good one',
      () async {
        access = FakeContentAccess(
          volumes: const ['external_primary', '5555-FFFF'],
          states: const {ContentCategory.images: ContentAccessState.fullAccess},
        );
        discovery.generation(ContentCategory.images, 'external_primary', null);
        discovery.generation(ContentCategory.images, '5555-FFFF', null);
        discovery.play(
          buildScript([
            ScriptUnit(
              category: ContentCategory.images,
              volume: 'external_primary',
              batches: [
                ([buildRecord(id: 1)], false, 1),
              ],
            ),
            ScriptUnit(
              category: ContentCategory.images,
              volume: '5555-FFFF',
              batches: [
                ([buildRecord(id: 2, volumeName: '5555-FFFF')], true, 2),
              ],
              error: true,
            ),
          ]),
        );

        final result = await run(const [ContentCategory.images]);

        expect(result.outcome, SyncSessionOutcome.partialFailure);
        expect(result.units, hasLength(2));
        final good = result.units.singleWhere(
          (u) => u.volumeName == 'external_primary',
        );
        final failed = result.units.singleWhere(
          (u) => u.volumeName == '5555-FFFF',
        );
        expect(good.kind, SyncUnitKind.firstIndex);
        expect(good.checkpointAdvanced, isTrue);
        expect(failed.kind, SyncUnitKind.failed);
        expect(failed.checkpointAdvanced, isFalse);
        expect(await repository.count(), 2);
      },
    );

    test('a clean run twice is idempotent (second is a fast-check)', () async {
      discovery.generation(ContentCategory.images, 'external_primary', 100);
      discovery.play(
        buildScript([
          ScriptUnit(
            category: ContentCategory.images,
            volume: 'external_primary',
            batches: [
              ([buildRecord(id: 1)], false, 100),
            ],
          ),
        ]),
      );

      final first = await run(const [ContentCategory.images]);
      expect(first.units.single.kind, SyncUnitKind.firstIndex);

      // No script queued now; the fast-check must skip the scan.
      final second = await run(const [ContentCategory.images]);
      expect(second.units.single.kind, SyncUnitKind.unchanged);
      expect(discovery.startedCategories, hasLength(1));
      expect(await repository.count(), 1);
    });

    test('unavailable categories are reported without scanning', () async {
      access = FakeContentAccess(
        volumes: const ['external_primary'],
        states: const {
          ContentCategory.images: ContentAccessState.fullAccess,
          ContentCategory.documents: ContentAccessState.noAccess,
        },
      );
      discovery.play(
        buildScript([
          ScriptUnit(
            category: ContentCategory.images,
            volume: 'external_primary',
            batches: [
              ([buildRecord(id: 1)], false, 10),
            ],
          ),
        ]),
      );

      final result = await run(const [
        ContentCategory.images,
        ContentCategory.documents,
      ]);

      expect(result.outcome, SyncSessionOutcome.completed);
      expect(result.units, hasLength(2));
      expect(result.units[0].kind, SyncUnitKind.firstIndex);
      expect(result.units[1].kind, SyncUnitKind.unavailable);
      expect(
        discovery.startedCategories,
        hasLength(1),
        reason: 'documents must never start a session',
      );
    });

    test(
      'a refused start fails every scan unit with the bridge code',
      () async {
        discovery.refuseStart = true;
        discovery.refuseCode = 'eventListenerNotAttached';

        final result = await run(const [ContentCategory.images]);

        expect(result.outcome, SyncSessionOutcome.failed);
        final unit = result.units.single;
        expect(unit.kind, SyncUnitKind.failed);
        expect(unit.errorCode, 'eventListenerNotAttached');
        expect(await repository.count(), 0);
        expect((await db.select(db.indexState).get()), isEmpty);
      },
    );

    test(
      'a cancellation marks units cancelled and writes no checkpoint',
      () async {
        discovery.generation(ContentCategory.images, 'external_primary', 100);
        discovery.play(
          buildScript([
            ScriptUnit(
              category: ContentCategory.images,
              volume: 'external_primary',
              batches: [
                ([buildRecord(id: 1)], true, 50),
              ],
              cancel: true,
            ),
          ]),
        );

        final result = await run(const [ContentCategory.images]);

        expect(result.outcome, SyncSessionOutcome.cancelled);
        expect(result.units.single.kind, SyncUnitKind.cancelled);
        expect(result.units.single.checkpointAdvanced, isFalse);
        // The engine window is explicitly unblocked on non-completed runs.
        expect(discovery.cancelCalls, 1);
        expect(
          await repository.count(),
          1,
          reason: 'the batch was persisted before cancellation',
        );
        expect((await db.select(db.indexState).get()), isEmpty);
      },
    );

    test('uses the fallback volume when none is reported', () async {
      access = FakeContentAccess(
        volumes: const [],
        states: const {ContentCategory.images: ContentAccessState.fullAccess},
      );
      discovery.play(
        buildScript([
          ScriptUnit(
            category: ContentCategory.images,
            volume: SynchronizationCoordinator.fallbackVolume,
            batches: [
              ([buildRecord(id: 1)], false, 5),
            ],
          ),
        ]),
      );

      final result = await run(const [ContentCategory.images]);

      expect(result.outcome, SyncSessionOutcome.completed);
      expect(
        result.units.single.volumeName,
        SynchronizationCoordinator.fallbackVolume,
      );
      expect(discovery.volumeFilters.single, [
        SynchronizationCoordinator.fallbackVolume,
      ]);
    });

    test('multi-volume unchanged fast-check skips both volumes', () async {
      access = FakeContentAccess(
        volumes: const ['external_primary', '5555-FFFF'],
        states: const {ContentCategory.images: ContentAccessState.fullAccess},
      );
      await seedCheckpoint();
      await seedCheckpoint(volume: '5555-FFFF');
      discovery.generation(ContentCategory.images, 'external_primary', 100);
      discovery.generation(ContentCategory.images, '5555-FFFF', 100);

      final result = await run(const [ContentCategory.images]);

      expect(result.outcome, SyncSessionOutcome.completed);
      expect(result.units, hasLength(2));
      expect(result.units.map((unit) => unit.kind), [
        SyncUnitKind.unchanged,
        SyncUnitKind.unchanged,
      ]);
      expect(discovery.startedCategories, isEmpty);
    });

    test('a multi-volume first run indexes every volume', () async {
      access = FakeContentAccess(
        volumes: const ['external_primary', '5555-FFFF'],
        states: const {ContentCategory.images: ContentAccessState.fullAccess},
      );
      discovery.generation(ContentCategory.images, 'external_primary', null);
      discovery.generation(ContentCategory.images, '5555-FFFF', null);
      discovery.play(
        buildScript([
          ScriptUnit(
            category: ContentCategory.images,
            volume: 'external_primary',
            batches: [
              ([buildRecord(id: 1)], false, 1),
            ],
          ),
          ScriptUnit(
            category: ContentCategory.images,
            volume: '5555-FFFF',
            batches: [
              ([buildRecord(id: 2, volumeName: '5555-FFFF')], false, 2),
            ],
          ),
        ]),
      );

      final result = await run(const [ContentCategory.images]);

      expect(result.outcome, SyncSessionOutcome.completed);
      expect(result.units, hasLength(2));
      expect(result.units.map((unit) => unit.kind), [
        SyncUnitKind.firstIndex,
        SyncUnitKind.firstIndex,
      ]);
      expect(await repository.count(), 2);
      final v1 = await repository.getSyncCheckpoint(
        ContentCategory.images,
        'external_primary',
      );
      final v2 = await repository.getSyncCheckpoint(
        ContentCategory.images,
        '5555-FFFF',
      );
      expect(v1!.lastGeneration, 1);
      expect(v2!.lastGeneration, 2);
    });
  });
}
