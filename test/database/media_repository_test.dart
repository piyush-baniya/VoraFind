import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_items_table.dart';
import 'package:vorafind/core/database/media_item_mapper.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/database/synchronization_coordinator.dart'
    show SyncUnitKind;
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart';

import 'test_support.dart';

void main() {
  group('DriftMediaRepository round-trips', () {
    late AppDatabase db;
    late DriftMediaRepository repository;

    setUp(() {
      db = inMemoryDb();
      repository = DriftMediaRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('persists every discovery field of an image record', () async {
      final record = buildRecord(
        id: 1,
        relinkSignature: 'sha256-signature',
        sizeBytes: 4242,
        dateAdded: 111,
        dateModified: 222,
        relativePath: 'DCIM/Camera/',
        bucketDisplayName: 'Camera',
        width: 4000,
        height: 3000,
        screenshotScore: 0,
        isScreenshot: false,
      );
      await repository.upsert(record, nowSeconds: 50);

      final row = await repository.fetchByStableKey('external_primary:1');
      expect(row!.category, 'images');
      expect(row.volumeName, 'external_primary');
      expect(row.mediaStoreId, 1);
      expect(row.contentUri, 'content://media/external_primary/images/media/1');
      expect(row.displayName, 'item_1.jpg');
      expect(row.relinkSignature, 'sha256-signature');
      expect(row.sizeBytes, 4242);
      expect(row.dateAdded, 111);
      expect(row.dateModified, 222);
      expect(row.relativePath, 'DCIM/Camera/');
      expect(row.bucketDisplayName, 'Camera');
      expect(row.width, 4000);
      expect(row.height, 3000);
      expect(row.screenshotScore, 0);
      expect(row.isScreenshot, isFalse);
      expect(row.firstDiscoveredAt, 50);
    });

    test(
      'audio metadata survives insertion as NULL-first then audio values',
      () async {
        await repository.upsert(buildRecord(id: 9));
        await repository.upsert(buildAudioRecord(id: 9));

        final row = await repository.fetchByStableKey('external_primary:9');
        expect(row!.artist, 'The Artist');
        expect(row.album, 'The Album');
        expect(row.title, 'Song title');
        expect(row.durationMs, 3 * 60 * 1000 + 15 * 1000);
        expect(row.mimeType, 'audio/mpeg');
      },
    );

    test('document record keeps nullable dimension fields null', () async {
      final record = buildRecord(
        id: 8,
        category: ContentCategory.documents,
        width: null,
        height: null,
        relinkSignature: null,
      );
      await repository.upsert(record);

      final row = await repository.fetchByStableKey('external_primary:8');
      expect(row!.width, isNull);
      expect(row.height, isNull);
      expect(row.relinkSignature, isNull);
      expect(row.mimeType, 'application/pdf');
    });

    test(
      're-upserting preserves indexingStatus seeded outside the repository',
      () async {
        await db
            .into(db.mediaItems)
            .insert(
              MediaItemsCompanion(
                stableKey: const Value('external_primary:3'),
                category: const Value('videos'),
                volumeName: const Value('external_primary'),
                mediaStoreId: const Value(3),
                contentUri: const Value(
                  'content://media/external/videos/media/3',
                ),
                displayName: const Value('clip.mp4'),
                firstDiscoveredAt: const Value(1),
                lastDiscoveredAt: const Value(1),
                metadataRevision: const Value(1),
                indexingStatus: const Value(IndexingStatus.pending),
              ),
              onConflict: DoNothing(),
            );

        await repository.upsert(
          buildRecord(
            id: 3,
            category: ContentCategory.videos,
            displayName: 'clip.mp4',
            mimeType: 'video/mp4',
          ),
        );

        final row = await repository.fetchByStableKey('external_primary:3');
        expect(row!.indexingStatus, IndexingStatus.pending);
        expect(row.metadataRevision, 2);
        expect(row.category, 'videos');
      },
    );

    test(
      'batch upsert is transactional and rolls back on mapper failure',
      () async {
        final db = inMemoryDb();
        final failingRepository = DriftMediaRepository(
          db,
          mapper: const ThrowingBatchMapper('external_primary:2'),
        );

        expect(
          () => failingRepository.upsertBatch([
            buildRecord(id: 1),
            buildRecord(id: 2),
            buildRecord(id: 3),
          ]),
          throwsA(isA<_MapperThrown>()),
        );

        // Nothing from the batch may be half-committed.
        final count = await DriftMediaRepository(
          db,
          mapper: const MediaItemMapper(),
        ).count();
        expect(count, 0);
        await db.close();
      },
    );
  });

  group('DriftMediaRepository incremental synchronization', () {
    late AppDatabase db;
    late DriftMediaRepository repository;

    setUp(() {
      db = inMemoryDb();
      repository = DriftMediaRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('upsertBatchChanged inserts new rows and reports counts', () async {
      final delta = await repository.upsertBatchChanged([
        buildRecord(id: 1),
        buildRecord(id: 2),
        buildRecord(id: 3),
      ]);

      expect(delta.inserted, 3);
      expect(delta.updated, 0);
      expect(delta.unchanged, 0);
      expect(delta.total, 3);
      expect(await repository.count(), 3);
    });

    test(
      'upsertBatchChanged skips identical rows without touching bookkeeping',
      () async {
        await repository.upsert(
          buildRecord(id: 1, displayName: 'a.jpg'),
          nowSeconds: 1000,
        );
        await repository.upsert(
          buildRecord(id: 1, displayName: 'a.jpg'),
          nowSeconds: 1001,
        );
        final before = await repository.fetchByStableKey('external_primary:1');

        final delta = await repository.upsertBatchChanged([
          buildRecord(id: 1, displayName: 'a.jpg'),
        ]);

        expect(delta.inserted, 0);
        expect(delta.updated, 0);
        expect(delta.unchanged, 1);
        // Unchanged rows are not written at all: no timestamp rewrite, no
        // revision bump.
        final after = await repository.fetchByStableKey('external_primary:1');
        expect(after!.lastDiscoveredAt, before!.lastDiscoveredAt);
        expect(after.metadataRevision, before.metadataRevision);
      },
    );

    test('upsertBatchChanged updates rows whose content changed', () async {
      await repository.upsert(buildRecord(id: 1, displayName: 'old.jpg'));

      final delta = await repository.upsertBatchChanged([
        buildRecord(id: 1, displayName: 'new.jpg'),
        buildRecord(id: 2),
      ]);

      expect(delta.updated, 1);
      expect(delta.inserted, 1);
      expect(delta.unchanged, 0);
      final row = await repository.fetchByStableKey('external_primary:1');
      expect(row!.displayName, 'new.jpg');
    });

    test(
      'fetchIndexedPage pages rows in ascending mediaStoreId order',
      () async {
        for (var id = 1; id <= 7; id++) {
          await repository.upsert(buildRecord(id: id));
        }
        await repository.upsert(buildRecord(id: 50, volumeName: 'other'));

        final first = await repository.fetchIndexedPage(
          category: ContentCategory.images,
          volumeName: 'external_primary',
          limit: 3,
        );
        expect(first.map((entry) => entry.mediaStoreId), [1, 2, 3]);

        final second = await repository.fetchIndexedPage(
          category: ContentCategory.images,
          volumeName: 'external_primary',
          afterId: first.last.mediaStoreId,
          limit: 3,
        );
        expect(second.map((entry) => entry.mediaStoreId), [4, 5, 6]);

        final third = await repository.fetchIndexedPage(
          category: ContentCategory.images,
          volumeName: 'external_primary',
          afterId: second.last.mediaStoreId,
          limit: 3,
        );
        expect(third.map((entry) => entry.mediaStoreId), [7]);
        expect(third.first.stableKey, 'external_primary:7');
      },
    );

    test('deleteByStableKeys removes exactly the requested rows', () async {
      for (var id = 1; id <= 4; id++) {
        await repository.upsert(buildRecord(id: id));
      }

      await repository.deleteByStableKeys([
        'external_primary:2',
        'external_primary:4',
      ]);

      expect(await repository.count(), 2);
      expect(await repository.fetchByStableKey('external_primary:2'), isNull);
      expect(
        await repository.fetchByStableKey('external_primary:3'),
        isNotNull,
      );
    });

    test('sync checkpoints round-trip and overwrite in place', () async {
      expect(
        await repository.getSyncCheckpoint(
          ContentCategory.images,
          'external_primary',
        ),
        isNull,
      );

      await repository.saveSyncCheckpoint(
        SyncCheckpoint(
          category: ContentCategory.images,
          volumeName: 'external_primary',
          lastGeneration: 42,
          lastAccessScope: DiscoveryAccessScope.full,
          lastSyncAt: 1000,
          lastResult: SyncUnitKind.firstIndex.name,
        ),
      );

      final saved = await repository.getSyncCheckpoint(
        ContentCategory.images,
        'external_primary',
      );
      expect(saved, isNotNull);
      expect(saved!.lastGeneration, 42);
      expect(saved.lastAccessScope, DiscoveryAccessScope.full);
      expect(saved.lastSyncAt, 1000);
      expect(saved.lastResult, SyncUnitKind.firstIndex.name);

      await repository.saveSyncCheckpoint(
        SyncCheckpoint(
          category: ContentCategory.images,
          volumeName: 'external_primary',
          lastGeneration: 43,
          lastAccessScope: DiscoveryAccessScope.partial,
          lastSyncAt: 2000,
          lastResult: SyncUnitKind.partialAccess.name,
        ),
      );
      final overwritten = await repository.getSyncCheckpoint(
        ContentCategory.images,
        'external_primary',
      );
      expect(overwritten!.lastGeneration, 43);
      expect(overwritten.lastAccessScope, DiscoveryAccessScope.partial);
      expect(
        (await db.select(db.indexState).get()).length,
        1,
        reason: 'checkpoints key on (category, volume) and must not duplicate',
      );
    });

    test('checkpoints are keyed per (category, volume) pair', () async {
      await repository.saveSyncCheckpoint(
        SyncCheckpoint(
          category: ContentCategory.images,
          volumeName: 'external_primary',
          lastGeneration: 1,
          lastAccessScope: DiscoveryAccessScope.full,
          lastSyncAt: 1,
          lastResult: SyncUnitKind.firstIndex.name,
        ),
      );
      await repository.saveSyncCheckpoint(
        SyncCheckpoint(
          category: ContentCategory.videos,
          volumeName: 'external_primary',
          lastGeneration: 2,
          lastAccessScope: DiscoveryAccessScope.full,
          lastSyncAt: 2,
          lastResult: SyncUnitKind.firstIndex.name,
        ),
      );
      await repository.saveSyncCheckpoint(
        SyncCheckpoint(
          category: ContentCategory.images,
          volumeName: '5555-ABCD',
          lastGeneration: 3,
          lastAccessScope: DiscoveryAccessScope.full,
          lastSyncAt: 3,
          lastResult: SyncUnitKind.firstIndex.name,
        ),
      );

      expect(await db.select(db.indexState).get(), hasLength(3));
      final second = await repository.getSyncCheckpoint(
        ContentCategory.videos,
        'external_primary',
      );
      expect(second!.lastGeneration, 2);
    });
  });
}

class _MapperThrown implements Exception {}

/// Mapper that fails when asked to insert the given stable key.
class ThrowingBatchMapper extends MediaItemMapper {
  const ThrowingBatchMapper(this.throwingKey);

  final String throwingKey;

  @override
  MediaItemsCompanion forInsert(
    MediaDiscoveryRecord record, {
    required int nowSeconds,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  }) {
    if (record.stableKey == throwingKey) {
      throw _MapperThrown();
    }
    return super.forInsert(
      record,
      nowSeconds: nowSeconds,
      generationAfter: generationAfter,
      accessScope: accessScope,
    );
  }
}
