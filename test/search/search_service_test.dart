import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_items_table.dart'
    show IndexingStatus;
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/search/search_error.dart';
import 'package:vorafind/core/search/search_query.dart';
import 'package:vorafind/core/search/search_result.dart';
import 'package:vorafind/core/search/search_service.dart';

void main() {
  group('SearchService.prepare', () {
    late AppDatabase db;
    late SearchService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      service = SearchService(repository: _FailingRepository(db));
    });

    tearDown(() => db.close());

    test('clamps negative and oversized limits', () {
      expect(service.prepare(const SearchQuery()).limit, 50);
      expect(service.prepare(const SearchQuery(limit: 0)).limit, 1);
      expect(service.prepare(const SearchQuery(limit: -5)).limit, 1);
      expect(service.prepare(const SearchQuery(limit: 9999)).limit, 200);
    });

    test('rejects negative bounds', () {
      expect(
        () => service.prepare(const SearchQuery(dateFrom: -1)),
        throwsA(isA<SearchException>()),
      );
      expect(
        () => service.prepare(const SearchQuery(minSizeBytes: -1)),
        throwsA(isA<SearchException>()),
      );
      expect(
        () => service.prepare(const SearchQuery(minDurationMs: -1)),
        throwsA(isA<SearchException>()),
      );
    });

    test('rejects inverted ranges', () {
      expect(
        () => service.prepare(const SearchQuery(dateFrom: 100, dateTo: 50)),
        throwsA(isA<SearchException>()),
      );
      expect(
        () => service.prepare(
          const SearchQuery(minSizeBytes: 100, maxSizeBytes: 50),
        ),
        throwsA(isA<SearchException>()),
      );
      expect(
        () => service.prepare(
          const SearchQuery(minDurationMs: 100, maxDurationMs: 50),
        ),
        throwsA(isA<SearchException>()),
      );
    });

    test('strips leading slashes from the path prefix', () {
      final prepared = service.prepare(const SearchQuery(pathPrefix: '/DCIM'));
      expect(prepared.pathPrefix, 'DCIM');
    });

    test('explicit filters override interpretation', () {
      final prepared = service.prepare(
        const SearchQuery(text: 'song', categories: [ContentCategory.images]),
      );
      expect(prepared.categories, [ContentCategory.images]);
      expect(prepared.tokens, isEmpty);
    });

    test('interprets media words and keeps the rest as keywords', () {
      final prepared = service.prepare(const SearchQuery(text: 'finance scan'));
      expect(prepared.tokens, ['finance', 'scan']);
      expect(prepared.hasKeyword, isTrue);
    });
  });

  group('SearchService.search', () {
    late AppDatabase db;
    late SearchService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      service = SearchService(repository: _FailingRepository(db));
    });

    tearDown(() => db.close());

    test('skips the index for an empty query', () async {
      final results = await service.search(const SearchQuery());
      expect(results, isEmpty);
    });

    test('surfaces repository failures as SearchException.database', () async {
      await expectLater(
        service.search(const SearchQuery(text: 'anything')),
        throwsA(
          isA<SearchException>().having(
            (e) => e.code,
            'code',
            SearchErrorCode.database,
          ),
        ),
      );
    });

    test('wraps invalid queries before touching the repository', () async {
      await expectLater(
        service.search(const SearchQuery(dateFrom: 10, dateTo: 5)),
        throwsA(
          isA<SearchException>().having(
            (e) => e.code,
            'code',
            SearchErrorCode.invalidQuery,
          ),
        ),
      );
    });

    test('returns ranked results in bounded form', () async {
      final ranked = SearchService(repository: _TwoRowRepository(db));
      final results = await ranked.search(
        const SearchQuery(text: 'citizen', limit: 1),
      );
      expect(results, hasLength(1));
      expect(results.single, isA<SearchResult>());
      expect(results.single.stableKey, 'k_citizen');
      expect(results.single.matches, isNotEmpty);
    });
  });
}

/// Repository contradiction: it *fails* on keyword retrieval, which proves the
/// service never touches it for empty/invalid queries and maps failures.
class _FailingRepository extends DriftMediaRepository {
  _FailingRepository(super.database);

  @override
  Future<List<MediaItem>> searchCandidates(NormalizedSearchQuery query) async {
    throw StateError('should not be reached');
  }
}

/// Tiny fixed pool so service-level ranking stays deterministic.
class _TwoRowRepository extends DriftMediaRepository {
  _TwoRowRepository(super.database);

  @override
  Future<List<MediaItem>> searchCandidates(NormalizedSearchQuery query) async {
    return [
      _row(key: 'k_citizen', name: 'citizen_front.jpg', date: 200),
      _row(key: 'k_family', name: 'family.jpg', date: 100),
    ];
  }
}

MediaItem _row({
  required String key,
  required String name,
  required int date,
}) => MediaItem(
  stableKey: key,
  category: 'images',
  volumeName: 'external_primary',
  mediaStoreId: 1,
  contentUri: 'content://media/external/images/media/1',
  displayName: name,
  title: null,
  mimeType: 'image/jpeg',
  sizeBytes: 100,
  dateAdded: null,
  dateModified: date,
  relativePath: null,
  bucketDisplayName: null,
  width: 100,
  height: 100,
  durationMs: null,
  artist: null,
  album: null,
  albumArtist: null,
  trackNumber: null,
  discNumber: null,
  genre: null,
  screenshotScore: null,
  isScreenshot: null,
  relinkSignature: null,
  searchableText: name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim(),
  firstDiscoveredAt: 1,
  lastDiscoveredAt: 1,
  lastIndexedGeneration: null,
  metadataRevision: 1,
  indexingStatus: IndexingStatus.none,
  lastSeenAccessScope: null,
);
