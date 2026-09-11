import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_items_table.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart';

import 'test_support.dart';

void main() {
  group('media_items database', () {
    late AppDatabase db;
    late DriftMediaRepository repository;

    setUp(() {
      db = inMemoryDb();
      repository = DriftMediaRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('empty database reports zero rows and no stats', () async {
      expect(await repository.count(), 0);
      final stats = await repository.stats();
      expect(stats.total, 0);
      expect(stats.byCategory, isEmpty);
      expect(stats.volumeCount, 0);
      expect(await repository.fetchByStableKey('external_primary:1'), isNull);
      expect(await repository.deleteByStableKey('external_primary:1'), isFalse);
    });

    test('insert one record and read it back', () async {
      await repository.upsert(buildRecord(id: 1), nowSeconds: 1000);

      final row = await repository.fetchByStableKey('external_primary:1');
      expect(row, isNotNull);
      expect(row!.stableKey, 'external_primary:1');
      expect(row.category, 'images');
      expect(row.volumeName, 'external_primary');
      expect(row.mediaStoreId, 1);
      expect(row.displayName, 'item_1.jpg');
      expect(await repository.count(), 1);
    });

    test(
      'upserting the same stable key does not create a duplicate row',
      () async {
        await repository.upsert(buildRecord(id: 1));
        await repository.upsert(buildRecord(id: 1));
        await repository.upsert(buildRecord(id: 1));

        expect(await repository.count(), 1);
        final rows = await repository.fetchByStableKeys(['external_primary:1']);
        expect(rows, hasLength(1));
      },
    );

    test('changed metadata updates the existing row in place', () async {
      await repository.upsert(
        buildRecord(id: 1, displayName: 'before.jpg', relinkSignature: 'sig-a'),
        nowSeconds: 1000,
      );
      await repository.upsert(
        buildRecord(id: 1, displayName: 'after.jpg', relinkSignature: 'sig-b'),
        nowSeconds: 2000,
      );

      final row = await repository.fetchByStableKey('external_primary:1');
      expect(row!.displayName, 'after.jpg');
      expect(row.relinkSignature, 'sig-b');
      expect(await repository.count(), 1);
    });

    test(
      'first discovered is preserved while last discovered advances',
      () async {
        await repository.upsert(buildRecord(id: 1), nowSeconds: 1000);
        await repository.upsert(
          buildRecord(id: 1, displayName: 'changed.jpg'),
          nowSeconds: 5000,
        );

        final row = await repository.fetchByStableKey('external_primary:1');
        expect(row!.firstDiscoveredAt, 1000);
        expect(row.lastDiscoveredAt, 5000);
        expect(row.metadataRevision, 2);
      },
    );

    test('metadata revision increments on every upsert', () async {
      await repository.upsert(buildRecord(id: 1));
      await repository.upsert(buildRecord(id: 1, displayName: 'v2.jpg'));
      await repository.upsert(buildRecord(id: 1, displayName: 'v3.jpg'));

      final row = await repository.fetchByStableKey('external_primary:1');
      expect(row!.metadataRevision, 3);
    });

    test(
      'a record seen under partial access records scope and generation',
      () async {
        await repository.upsert(
          buildRecord(id: 1),
          accessScope: DiscoveryAccessScope.partial,
          generationAfter: 42,
        );

        final row = await repository.fetchByStableKey('external_primary:1');
        expect(row!.lastSeenAccessScope, 'partial');
        expect(row.lastIndexedGeneration, 42);
      },
    );

    test(
      'multiple records across categories and volumes are counted',
      () async {
        await repository.upsert(
          buildRecord(id: 1, category: ContentCategory.images),
        );
        await repository.upsert(
          buildRecord(id: 2, category: ContentCategory.videos),
        );
        await repository.upsert(
          buildRecord(id: 3, category: ContentCategory.audio),
        );
        await repository.upsert(buildRecord(id: 4, volumeName: 'external_sd'));

        expect(await repository.count(), 4);
        final stats = await repository.stats();
        expect(stats.total, 4);
        expect(stats.countOf(ContentCategory.images), 2);
        expect(stats.countOf(ContentCategory.videos), 1);
        expect(stats.countOf(ContentCategory.audio), 1);
        expect(stats.volumeCount, 2);
      },
    );

    test('batch upsert commits every row of the batch', () async {
      final written = await repository.upsertBatch([
        buildRecord(id: 1),
        buildRecord(id: 2),
        buildRecord(id: 3),
      ], nowSeconds: 777);

      expect(written, 3);
      expect(await repository.count(), 3);
    });

    test('delete by stable key removes exactly one row', () async {
      await repository.upsert(buildRecord(id: 1));
      await repository.upsert(buildRecord(id: 2));

      expect(await repository.deleteByStableKey('external_primary:1'), isTrue);
      expect(await repository.count(), 1);
      expect(await repository.fetchByStableKey('external_primary:1'), isNull);
      expect(await repository.deleteByStableKey('external_primary:1'), isFalse);
    });

    test('clearAll resets the local index', () async {
      await repository.upsertBatch([buildRecord(id: 1), buildRecord(id: 2)]);
      await repository.clearAll();

      expect(await repository.count(), 0);
    });

    test('fetchByStableKeys returns only matching rows', () async {
      await repository.upsert(buildRecord(id: 1));
      await repository.upsert(buildRecord(id: 2));

      final rows = await repository.fetchByStableKeys([
        'external_primary:1',
        'external_primary:999',
      ]);
      expect(rows.map((r) => r.mediaStoreId), [1]);
    });

    test('a scan that omits a row never deletes it (partial access)', () async {
      await repository.upsert(buildRecord(id: 1));

      // A later partial scan returns only id=2; id=1 must still exist.
      await repository.upsertBatch([buildRecord(id: 2)]);

      expect(await repository.count(), 2);
      expect(
        await repository.fetchByStableKey('external_primary:1'),
        isNotNull,
      );
    });

    test('data persists across close and reopen (durability)', () async {
      final directory = Directory.current.createTempSync('vorafind_db_test');
      final path = '${directory.path}${Platform.pathSeparator}durable.sqlite';

      final first = AppDatabase(NativeDatabase(File(path)));
      await first
          .into(first.mediaItems)
          .insert(
            MediaItemsCompanion(
              stableKey: const Value('external_primary:7'),
              category: const Value('images'),
              volumeName: const Value('external_primary'),
              mediaStoreId: const Value(7),
              contentUri: const Value(
                'content://media/external/images/media/7',
              ),
              displayName: const Value('durable.jpg'),
              firstDiscoveredAt: const Value(1000),
              lastDiscoveredAt: const Value(1000),
              metadataRevision: const Value(1),
              indexingStatus: const Value(IndexingStatus.none),
            ),
          );
      await first.close();

      final second = AppDatabase(NativeDatabase(File(path)));
      final row = await second.select(second.mediaItems).getSingle();
      expect(row.stableKey, 'external_primary:7');
      expect(row.displayName, 'durable.jpg');
      await second.close();

      directory.deleteSync(recursive: true);
    });

    test('migration creates the expected initial schema (v1)', () async {
      final userVersion = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(userVersion.data.values.single, 1);
      final columns = await db
          .customSelect('PRAGMA table_info(media_items)')
          .get()
          .then((rows) => rows.map((r) => r.data['name']).toSet());
      expect(
        columns,
        containsAll({
          'stable_key',
          'category',
          'volume_name',
          'media_store_id',
          'content_uri',
          'display_name',
          'title',
          'mime_type',
          'size_bytes',
          'date_added',
          'date_modified',
          'relative_path',
          'bucket_display_name',
          'width',
          'height',
          'duration_ms',
          'artist',
          'album',
          'album_artist',
          'track_number',
          'disc_number',
          'genre',
          'screenshot_score',
          'is_screenshot',
          'relink_signature',
          'first_discovered_at',
          'last_discovered_at',
          'last_indexed_generation',
          'metadata_revision',
          'indexing_status',
          'last_seen_access_scope',
        }),
      );
    });
  });
}
