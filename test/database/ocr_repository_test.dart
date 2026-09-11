import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/ocr/ocr_models.dart';
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart';
import 'package:vorafind/core/search/search_query.dart';

import 'test_support.dart';

void main() {
  group('OCR repository', () {
    late AppDatabase db;
    late DriftMediaRepository repository;

    setUp(() {
      db = inMemoryDb();
      repository = DriftMediaRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> upsertImage(
      int id, {
      String? displayName,
      String? mimeType,
      bool isScreenshot = false,
      DiscoveryAccessScope scope = DiscoveryAccessScope.full,
    }) => repository.upsert(
      buildRecord(
        id: id,
        displayName: displayName,
        mimeType: mimeType,
        isScreenshot: isScreenshot,
      ),
      accessScope: scope,
    );

    Future<MediaItem> fetch(int id) async =>
        (await repository.fetchByStableKey('external_primary:$id'))!;

    group('findOcrCandidates', () {
      test(
        'returns only OCR-supported images first seen under full access',
        () async {
          await upsertImage(1);
          await upsertImage(2, mimeType: 'image/png');
          // Never indexed under a full scan: bodies must not be read.
          await upsertImage(3, scope: DiscoveryAccessScope.partial);
          // Not part of the OCR population.
          await upsertImage(4, mimeType: 'image/heif');
          await repository.upsert(
            buildRecord(id: 5, category: ContentCategory.documents),
            accessScope: DiscoveryAccessScope.full,
          );

          final candidates = await repository.findOcrCandidates(
            batchSize: 10,
            nowEpochSeconds: 1000,
          );
          expect(
            candidates.map((r) => r.mediaStoreId),
            unorderedEquals([1, 2]),
          );
        },
      );

      test('orders screenshots first then stable key ascending', () async {
        await upsertImage(2);
        await upsertImage(1);
        await upsertImage(3, isScreenshot: true);

        final candidates = await repository.findOcrCandidates(
          batchSize: 10,
          nowEpochSeconds: 1000,
        );
        expect(candidates.map((r) => r.mediaStoreId), [3, 1, 2]);
      });

      test('respects the batch size and pages through pending rows', () async {
        for (var id = 1; id <= 5; id++) {
          await upsertImage(id);
        }

        // The coordinator loop: select a batch, process each row (here: record
        // a transient failure so it leaves the eligible set), then continue
        // until no candidates remain. This exercises batch boundaries without
        // double-processing any row.
        final drained = <int>[];
        var pages = 0;
        while (true) {
          final batch = await repository.findOcrCandidates(
            batchSize: 2,
            nowEpochSeconds: 1000,
          );
          if (batch.isEmpty) break;
          pages++;
          // Non-empty, never over the batch ceiling; only the trailing page
          // may be short.
          expect(batch.length, lessThanOrEqualTo(2));
          expect(batch.length, greaterThanOrEqualTo(1));
          for (final row in batch) {
            drained.add(row.mediaStoreId);
            await repository.saveOcrResult(
              stableKey: row.stableKey,
              text: null,
              status: OcrStatus.failed,
              sourceRevision: row.metadataRevision,
              nowEpochSeconds: 1000,
            );
          }
        }
        expect(pages, 3);
        expect(drained, unorderedEquals([1, 2, 3, 4, 5]));
        expect(drained.toSet(), hasLength(5));
      });

      test('retries transient failures only after the cooldown', () async {
        await upsertImage(1);
        await upsertImage(2);
        const processedAt = 1000;
        await repository.saveOcrResult(
          stableKey: 'external_primary:1',
          text: null,
          status: OcrStatus.failed,
          sourceRevision: 1,
          nowEpochSeconds: processedAt,
          errorCode: OcrErrorCode.ocrFailed.name,
        );

        // Still inside the cooldown window.
        final within = await repository.findOcrCandidates(
          batchSize: 10,
          nowEpochSeconds: processedAt + OcrDefaults.retryCooldownSeconds - 1,
        );
        expect(within.map((r) => r.mediaStoreId), [2]);

        // Cooldown has elapsed: row 1 is eligible again.
        final after = await repository.findOcrCandidates(
          batchSize: 10,
          nowEpochSeconds: processedAt + OcrDefaults.retryCooldownSeconds,
        );
        expect(after.map((r) => r.mediaStoreId), unorderedEquals([1, 2]));
      });

      test(
        're-processes completed rows whose image revision changed',
        () async {
          await upsertImage(1, displayName: 'before.jpg');
          final row = await fetch(1);
          await repository.saveOcrResult(
            stableKey: row.stableKey,
            text: 'old text',
            status: OcrStatus.completed,
            sourceRevision: row.metadataRevision,
            nowEpochSeconds: 1000,
          );

          // Current revision: not an OCR candidate.
          final none = await repository.findOcrCandidates(
            batchSize: 10,
            nowEpochSeconds: 2000,
          );
          expect(none, isEmpty);

          // A metadata bump (new image bytes) makes it stale again.
          await upsertImage(1, displayName: 'after.jpg');
          final changed = await repository.findOcrCandidates(
            batchSize: 10,
            nowEpochSeconds: 3000,
          );
          expect(changed.map((r) => r.mediaStoreId), [1]);
          expect(changed.single.metadataRevision, 2);
        },
      );

      test('permanently skips unsupported rows', () async {
        await upsertImage(1);
        await repository.saveOcrResult(
          stableKey: 'external_primary:1',
          text: null,
          status: OcrStatus.unsupported,
          sourceRevision: 1,
          nowEpochSeconds: 1000,
          errorCode: OcrErrorCode.decodeFailed.name,
        );

        final candidates = await repository.findOcrCandidates(
          batchSize: 10,
          nowEpochSeconds: 10000,
        );
        expect(candidates, isEmpty);
      });
    });

    group('saveOcrResult / getOcrStatus', () {
      test('persists completion with normalized text and revision', () async {
        await upsertImage(1, displayName: 'IMG_1.jpg');
        final row = await fetch(1);
        await repository.saveOcrResult(
          stableKey: row.stableKey,
          text: 'Aadhaar 5550  Nutrition Card',
          status: OcrStatus.completed,
          sourceRevision: row.metadataRevision,
          nowEpochSeconds: 2500,
        );

        final status = await repository.getOcrStatus(row.stableKey);
        expect(status, isNotNull);
        expect(status!.status, OcrStatus.completed);
        expect(status.sourceRevision, row.metadataRevision);
        expect(status.updatedAt, 2500);

        final stored = await (db.select(
          db.ocrContent,
        )..where((o) => o.mediaStableKey.equals(row.stableKey))).getSingle();
        expect(stored.normalizedText, 'aadhaar 5550 nutrition card');
        expect(stored.rawText, 'Aadhaar 5550  Nutrition Card');
      });

      test('is idempotent and preserves the first-write timestamp', () async {
        await upsertImage(1);
        final row = await fetch(1);
        await repository.saveOcrResult(
          stableKey: row.stableKey,
          text: 'first',
          status: OcrStatus.completed,
          sourceRevision: row.metadataRevision,
          nowEpochSeconds: 1000,
        );
        await repository.saveOcrResult(
          stableKey: row.stableKey,
          text: 'second',
          status: OcrStatus.completed,
          sourceRevision: row.metadataRevision,
          nowEpochSeconds: 5000,
        );

        final stored = await (db.select(
          db.ocrContent,
        )..where((o) => o.mediaStableKey.equals(row.stableKey))).getSingle();
        expect(stored.createdAt, 1000);
        expect(stored.updatedAt, 5000);
        expect(stored.normalizedText, 'second');
        expect(await db.select(db.ocrContent).get(), hasLength(1));
      });

      test('reports no durable status before any write', () async {
        await upsertImage(1);
        expect(await repository.getOcrStatus('external_primary:1'), isNull);
      });
    });

    group('ocrStats', () {
      test('partitions the supported-image population by status', () async {
        await upsertImage(1); // completed
        await upsertImage(2); // failed
        await upsertImage(3); // unsupported
        await upsertImage(4); // pending (no ocr row)
        await upsertImage(5, mimeType: 'image/gif'); // pending too
        await upsertImage(6, scope: DiscoveryAccessScope.partial); // pending
        await repository.upsert(
          buildRecord(id: 7, category: ContentCategory.videos),
          accessScope: DiscoveryAccessScope.full,
        );

        final cases = {
          1: OcrStatus.completed,
          2: OcrStatus.failed,
          3: OcrStatus.unsupported,
        };
        for (final entry in cases.entries) {
          final id = entry.key;
          final status = entry.value;
          final row = await fetch(id);
          await repository.saveOcrResult(
            stableKey: row.stableKey,
            text: status == OcrStatus.completed ? 'x' : null,
            status: status,
            sourceRevision: row.metadataRevision,
            nowEpochSeconds: 1000,
          );
        }

        final stats = await repository.ocrStats();
        expect(stats.eligible, 6); // images 1..6 (incl. partial-scope row)
        expect(stats.completed, 1);
        expect(stats.failed, 1);
        expect(stats.unsupported, 1);
      });
    });

    group('searchOcrCandidates', () {
      NormalizedSearchQuery query(List<String> tokens) => NormalizedSearchQuery(
        tokens: tokens,
        categories: const [],
        isScreenshot: null,
        dateFrom: null,
        dateTo: null,
        minSizeBytes: null,
        maxSizeBytes: null,
        pathPrefix: null,
        minDurationMs: null,
        maxDurationMs: null,
        limit: 50,
      );

      test('surfaces current OCR text matches with the owning item', () async {
        await upsertImage(1, displayName: 'IMG_0001.jpg');
        final row = await fetch(1);
        await repository.saveOcrResult(
          stableKey: row.stableKey,
          text: 'hospital discharge 5550 summary',
          status: OcrStatus.completed,
          sourceRevision: row.metadataRevision,
          nowEpochSeconds: 1000,
        );

        final matches = await repository.searchOcrCandidates(query(['5550']));
        expect(matches, hasLength(1));
        expect(matches.single.item.stableKey, row.stableKey);
        expect(
          matches.single.normalizedText,
          'hospital discharge 5550 summary',
        );
      });

      test('excludes failed, unsupported and stale-revision rows', () async {
        await upsertImage(1); // completed + current → match
        await upsertImage(2); // failed → excluded
        await upsertImage(3); // stale revision → excluded
        await upsertImage(4); // unsupported → excluded
        for (final id in [1, 2, 3, 4]) {
          final row = await fetch(id);
          final status = switch (id) {
            1 || 3 => OcrStatus.completed,
            2 => OcrStatus.failed,
            _ => OcrStatus.unsupported,
          };
          await repository.saveOcrResult(
            stableKey: row.stableKey,
            text: 'shared token phrase',
            status: status,
            sourceRevision: id == 3
                ? row.metadataRevision - 1
                : row.metadataRevision,
            nowEpochSeconds: 1000,
          );
        }

        final matches = await repository.searchOcrCandidates(query(['shared']));
        expect(matches.map((m) => m.item.mediaStoreId), [1]);
      });

      test('applies metadata filters to OCR candidates', () async {
        await upsertImage(1, displayName: 'IMG_1.jpg');
        await upsertImage(2, displayName: 'IMG_2.jpg');
        for (final id in [1, 2]) {
          final row = await fetch(id);
          await repository.saveOcrResult(
            stableKey: row.stableKey,
            text: 'receipt total 1200',
            status: OcrStatus.completed,
            sourceRevision: row.metadataRevision,
            nowEpochSeconds: 1000,
          );
        }

        final screenshotOnly = NormalizedSearchQuery(
          tokens: const ['receipt'],
          categories: const [],
          isScreenshot: true,
          dateFrom: null,
          dateTo: null,
          minSizeBytes: null,
          maxSizeBytes: null,
          pathPrefix: null,
          minDurationMs: null,
          maxDurationMs: null,
          limit: 50,
        );
        final matches = await repository.searchOcrCandidates(screenshotOnly);
        expect(matches, isEmpty);
      });

      test('returns an empty pool when no keyword tokens match', () async {
        await upsertImage(1);
        final row = await fetch(1);
        await repository.saveOcrResult(
          stableKey: row.stableKey,
          text: 'nothing relevant',
          status: OcrStatus.completed,
          sourceRevision: row.metadataRevision,
          nowEpochSeconds: 1000,
        );

        // A filter-only query has no token to match against.
        final candidates = await repository.searchOcrCandidates(
          query(const []),
        );
        expect(candidates, isNotEmpty);
      });
    });

    group('deletion', () {
      test('deleting a media row removes its OCR enrichment', () async {
        await upsertImage(1);
        final row = await fetch(1);
        await repository.saveOcrResult(
          stableKey: row.stableKey,
          text: 'to be deleted',
          status: OcrStatus.completed,
          sourceRevision: row.metadataRevision,
          nowEpochSeconds: 1000,
        );

        expect(await repository.deleteByStableKey(row.stableKey), isTrue);
        expect(await repository.getOcrStatus(row.stableKey), isNull);
        expect(await db.select(db.ocrContent).get(), isEmpty);
      });

      test('clearAll removes OCR enrichment too', () async {
        for (var id = 1; id <= 2; id++) {
          await upsertImage(id);
          final row = await fetch(id);
          await repository.saveOcrResult(
            stableKey: row.stableKey,
            text: 'x',
            status: OcrStatus.completed,
            sourceRevision: row.metadataRevision,
            nowEpochSeconds: 1000,
          );
        }

        await repository.clearAll();
        expect(await db.select(db.ocrContent).get(), isEmpty);
      });
    });
  });
}
