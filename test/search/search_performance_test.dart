import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_items_table.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/search/search_normalizer.dart';
import 'package:vorafind/core/search/search_query.dart';
import 'package:vorafind/core/search/search_service.dart';

/// Smoke benchmark (docs `search.md` §Performance test).
///
/// Methodology: seed a library-sized index (5000 photo rows), run one keyword
/// search through the full stack (SQL candidate retrieval + Dart ranking), and
/// assert a generous wall-clock budget. This is intentionally NOT a portable
/// latency claim — CI boxes and phones differ by orders of magnitude. It only
/// guards against quadratic/whole-library regressions: if substring matching
/// ever stopped scanning a single indexed column, this threshold would blow up
/// far beyond 10s.
void main() {
  test('search over a 5000-row index stays far under budget', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = DriftMediaRepository(db);
    final service = SearchService(repository: repository);

    await db.transaction(() async {
      await db.batch((batch) {
        for (var id = 1; id <= 5000; id++) {
          final name = 'photo_$id.jpg';
          batch.insert(
            db.mediaItems,
            MediaItemsCompanion(
              stableKey: Value('external_primary:$id'),
              category: const Value('images'),
              volumeName: const Value('external_primary'),
              mediaStoreId: Value(id),
              contentUri: Value(
                'content://media/external_primary/images/media/$id',
              ),
              displayName: Value(name),
              searchableText: Value(
                SearchNormalizer.storageText([name, 'DCIM/Camera/', 'Camera']),
              ),
              firstDiscoveredAt: Value(1000 + id),
              lastDiscoveredAt: Value(1000 + id),
              metadataRevision: const Value(1),
              indexingStatus: const Value(IndexingStatus.none),
            ),
          );
        }
      });
    });

    final stopwatch = Stopwatch()..start();
    final results = await service.search(
      const SearchQuery(text: 'photo 4321', limit: 50),
    );
    stopwatch.stop();

    expect(results, hasLength(lessThanOrEqualTo(50)));
    // Both tokens match photo_4321.jpg, so it wins over single-token hits.
    expect(results.first.displayName, 'photo_4321.jpg');
    expect(
      stopwatch.elapsedMilliseconds,
      lessThan(10_000),
      reason: 'keyword search should stay bounded on a 5000-row index',
    );
  });
}
