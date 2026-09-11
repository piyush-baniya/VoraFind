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
import 'package:vorafind/core/search/search_query.dart';

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

  group('DriftMediaRepository.searchCandidates', () {
    late AppDatabase db;
    late DriftMediaRepository repository;

    setUp(() {
      db = inMemoryDb();
      repository = DriftMediaRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seed(MediaDiscoveryRecord record) =>
        repository.upsert(record, nowSeconds: record.dateModified ?? 1000);

    test(
      'matches keywords case-insensitively across the searchable text',
      () async {
        await seed(buildRecord(id: 1, displayName: 'Citizenship_Front.JPG'));
        await seed(buildRecord(id: 2, displayName: 'family_vacation.jpg'));

        final results = await repository.searchCandidates(
          _query(tokens: ['citizenship']),
        );
        expect(results.map((r) => r.stableKey), ['external_primary:1']);
      },
    );

    test('matches title and artist metadata, not only filenames', () async {
      await seed(buildAudioRecord(id: 10));
      final byTitle = await repository.searchCandidates(
        _query(tokens: ['holiday', 'artist']),
      );
      // buildAudioRecord has title 'Song title', artist 'The Artist',
      // album 'The Album', plus default relativePath/bucket names.
      expect(byTitle.map((r) => r.stableKey), contains('external_primary:10'));
    });

    test(
      'multi-token keyword search is an OR and coverage order dominates',
      () async {
        await seed(
          buildRecord(
            id: 1,
            displayName: 'flutter_notes_v1.pdf',
            category: ContentCategory.documents,
            relativePath: 'Documents/Notes/',
          ),
        );
        await seed(
          buildRecord(
            id: 2,
            displayName: 'flutter_error_screenshot.png',
            isScreenshot: true,
          ),
        );
        await seed(buildRecord(id: 3, displayName: 'family.jpg'));

        final results = await repository.searchCandidates(
          _query(tokens: ['flutter', 'notes']),
        );
        expect(
          results.map((r) => r.stableKey),
          containsAll(['external_primary:1', 'external_primary:2']),
        );
        // Row 1 covers both tokens (flutter + notes); row 2 only one.
        expect(results.first.stableKey, 'external_primary:1');
      },
    );

    test('category filter narrows keyword results', () async {
      await seed(buildRecord(id: 1, displayName: 'trip.jpg'));
      await seed(buildAudioRecord(id: 2));
      await seed(
        buildRecord(
          id: 3,
          displayName: 'trip.mp4',
          category: ContentCategory.videos,
        ),
      );

      final results = await repository.searchCandidates(
        _query(tokens: ['trip'], categories: [ContentCategory.images]),
      );
      expect(results.single.stableKey, 'external_primary:1');
    });

    test('screenshot filter is respected', () async {
      await seed(
        buildRecord(id: 1, displayName: 'screen.png', isScreenshot: true),
      );
      await seed(
        buildRecord(id: 2, displayName: 'screen.png', isScreenshot: false),
      );

      final results = await repository.searchCandidates(
        _query(tokens: ['screen'], isScreenshot: true),
      );
      expect(results.single.stableKey, 'external_primary:1');
    });

    test('date, size and duration ranges filter rows', () async {
      await seed(
        buildRecord(
          id: 1,
          displayName: 'old.jpg',
          dateModified: 100,
          sizeBytes: 1000,
        ),
      );
      await seed(
        buildRecord(
          id: 2,
          displayName: 'new.jpg',
          dateModified: 500,
          sizeBytes: 5000,
          durationMs: 90_000,
          category: ContentCategory.videos,
        ),
      );

      final dated = await repository.searchCandidates(
        _query(dateFrom: 300, tokens: []),
      );
      expect(dated.single.stableKey, 'external_primary:2');

      final sized = await repository.searchCandidates(
        _query(tokens: ['jpg'], minSizeBytes: 2000),
      );
      expect(sized.single.stableKey, 'external_primary:2');

      final timed = await repository.searchCandidates(
        _query(tokens: [], minDurationMs: 60_000, maxDurationMs: 120_000),
      );
      expect(timed.map((r) => r.stableKey), contains('external_primary:2'));
    });

    test(
      'path prefix matches folder names with LIKE wildcards as literals',
      () async {
        await seed(
          buildRecord(
            id: 1,
            displayName: 'doc.pdf',
            relativePath: '100%_Done/Reports/',
          ),
        );
        await seed(
          buildRecord(
            id: 2,
            displayName: 'doc.pdf',
            relativePath: 'Done/Reports/',
          ),
        );

        // '%' and '_' are literal in the user's prefix, not wildcards.
        final withWildcards = await repository.searchCandidates(
          _query(tokens: ['doc'], pathPrefix: '100%_Done'),
        );
        expect(withWildcards.single.stableKey, 'external_primary:1');

        final plain = await repository.searchCandidates(
          _query(tokens: ['doc'], pathPrefix: 'Done'),
        );
        expect(plain.single.stableKey, 'external_primary:2');
      },
    );

    test(
      'filter-only search returns the limit directly in recency order',
      () async {
        for (var id = 1; id <= 5; id++) {
          await seed(buildRecord(id: id, dateModified: 100 + id));
        }
        final results = await repository.searchCandidates(
          _query(tokens: const [], limit: 3),
        );
        expect(results, hasLength(3));
        // Most recently modified first.
        expect(results.first.stableKey, 'external_primary:5');
      },
    );

    test(
      'keyword search pool is bounded by limit times multiple, capped',
      () async {
        for (var id = 1; id <= 100; id++) {
          await seed(buildRecord(id: id, displayName: 'hit_$id.jpg'));
        }
        final results = await repository.searchCandidates(
          _query(tokens: ['hit'], limit: 10),
        );
        // min(10 * 4, 400) — never the whole index.
        expect(results, hasLength(40));
      },
    );

    test('no matches returns an empty list', () async {
      await seed(buildRecord(id: 1, displayName: 'family.jpg'));
      final results = await repository.searchCandidates(
        _query(tokens: ['zebra']),
      );
      expect(results, isEmpty);
    });

    test('only committed rows are visible to search', () async {
      await expectLater(
        db.transaction(() async {
          await db
              .into(db.mediaItems)
              .insert(
                MediaItemsCompanion(
                  stableKey: const Value('external_primary:99'),
                  category: const Value('images'),
                  volumeName: const Value('external_primary'),
                  mediaStoreId: const Value(99),
                  contentUri: const Value(
                    'content://media/external_primary/images/media/99',
                  ),
                  displayName: const Value('rollback.jpg'),
                  firstDiscoveredAt: const Value(1),
                  lastDiscoveredAt: const Value(1),
                  metadataRevision: const Value(1),
                  indexingStatus: const Value(IndexingStatus.none),
                ),
              );
          throw _RollbackNow();
        }),
        throwsA(isA<_RollbackNow>()),
      );

      final before = await repository.searchCandidates(
        _query(tokens: ['rollback']),
      );
      expect(before, isEmpty);

      await repository.upsert(buildRecord(id: 99, displayName: 'rollback.jpg'));
      final after = await repository.searchCandidates(
        _query(tokens: ['rollback']),
      );
      expect(after.single.stableKey, 'external_primary:99');
    });
  });
}

class _RollbackNow implements Exception {}

NormalizedSearchQuery _query({
  List<String> tokens = const [],
  List<ContentCategory> categories = const [],
  bool? isScreenshot,
  int? dateFrom,
  int? dateTo,
  int? minSizeBytes,
  int? maxSizeBytes,
  String? pathPrefix,
  int? minDurationMs,
  int? maxDurationMs,
  int limit = 50,
}) => NormalizedSearchQuery(
  tokens: tokens,
  categories: categories,
  isScreenshot: isScreenshot,
  dateFrom: dateFrom,
  dateTo: dateTo,
  minSizeBytes: minSizeBytes,
  maxSizeBytes: maxSizeBytes,
  pathPrefix: pathPrefix,
  minDurationMs: minDurationMs,
  maxDurationMs: maxDurationMs,
  limit: limit,
);

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
