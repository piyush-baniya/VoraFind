import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_items_table.dart';
import 'package:vorafind/core/database/media_item_mapper.dart';
import 'package:vorafind/core/database/media_repository.dart';
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
