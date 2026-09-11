import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/document_repository.dart';
import 'package:vorafind/core/database/media_items_table.dart'
    show IndexingStatus;
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/documents/document_models.dart'
    show DocumentAccessState;
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/search/search_error.dart';
import 'package:vorafind/core/search/search_field.dart';
import 'package:vorafind/core/search/search_query.dart';
import 'package:vorafind/core/search/search_result.dart';
import 'package:vorafind/core/search/search_service.dart';
import 'package:vorafind/core/semantic/embedding_provider.dart';
import 'package:vorafind/core/semantic/semantic_models.dart';
import 'package:vorafind/core/semantic/semantic_repository.dart';

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

  group('SearchService.search hybrid semantic', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('semantic-only media rows are resolved and never crash the ranker', () async {
      final service = SearchService(
        repository: _SemanticMediaRepository(db),
        semanticSearchRepository: _FixedSemanticRepository(const [
          SemanticMatch(
            stableKey: 'k_sem',
            contentType: SemanticContentType.media,
            similarity: 0.6,
          ),
        ]),
        // Disconnected from the real model: this provider only needs to be
        // available so the hybrid path runs (Prompt #14 regression — the bug it
        // pins crashed with "Null check operator used on a null value").
        embeddingProvider: const DeterministicEmbeddingProvider(),
      );

      final results = await service.search(
        const SearchQuery(text: 'pixel', limit: 20),
      );
      expect(results, hasLength(2));
      final resolved = results.firstWhere((r) => r.stableKey == 'k_sem');
      expect(resolved.category, ContentCategory.images);
      expect(resolved.displayName, 'mountain_photo.jpg');
      expect(
        resolved.matches.any((m) => m.field == SearchField.semantic),
        isTrue,
      );
      expect(resolved.score, greaterThan(0));
    });

    test(
      'semantic-only document rows are resolved through the document index',
      () async {
        final service = SearchService(
          repository: _NoRowsRepository(db),
          documentRepository: _SemanticDocumentRepository(db),
          semanticSearchRepository: _FixedSemanticRepository(const [
            SemanticMatch(
              stableKey: 'doc_k_sem',
              contentType: SemanticContentType.document,
              similarity: 0.6,
            ),
          ]),
          embeddingProvider: const DeterministicEmbeddingProvider(),
        );

        final results = await service.search(
          const SearchQuery(text: 'zzz', limit: 20),
        );
        expect(results, hasLength(1));
        expect(results.single.stableKey, 'doc_k_sem');
        expect(results.single.category, ContentCategory.documents);
        expect(results.single.displayName, 'untitled_machine_learning.pdf');
        expect(
          results.single.matches.any((m) => m.field == SearchField.semantic),
          isTrue,
        );
      },
    );
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

/// Keyword pool that only returns [k_pixel]; the semantic hit (k_sem) is
/// entirely absent from the keyword pools so the unresolved path is exercised.
class _SemanticMediaRepository extends DriftMediaRepository {
  _SemanticMediaRepository(super.database);

  @override
  Future<List<MediaItem>> searchCandidates(NormalizedSearchQuery query) async =>
      [_row(key: 'k_pixel', name: 'pixel_photo.jpg', date: 100)];

  @override
  Future<List<OcrSearchMatch>> searchOcrCandidates(
    NormalizedSearchQuery query,
  ) async => const [];

  @override
  Future<List<MediaItem>> fetchByStableKeys(Iterable<String> stableKeys) async {
    if (stableKeys.contains('k_sem')) {
      return [_row(key: 'k_sem', name: 'mountain_photo.jpg', date: 200)];
    }
    return const [];
  }
}

class _NoRowsRepository extends DriftMediaRepository {
  _NoRowsRepository(super.database);

  @override
  Future<List<MediaItem>> searchCandidates(NormalizedSearchQuery query) async =>
      const [];

  @override
  Future<List<OcrSearchMatch>> searchOcrCandidates(
    NormalizedSearchQuery query,
  ) async => const [];
}

class _SemanticDocumentRepository extends DriftDocumentRepository {
  _SemanticDocumentRepository(super.db);

  @override
  Future<List<DocumentSearchMatch>> searchDocumentCandidates(
    NormalizedSearchQuery query,
  ) async => const [];

  @override
  Future<List<DocumentSearchMatch>> searchDocumentContentCandidates(
    NormalizedSearchQuery query,
  ) async => const [];

  @override
  Future<Document?> fetchByStableKey(String stableKey) async {
    if (stableKey != 'doc_k_sem') return null;
    final name = 'untitled_machine_learning.pdf';
    return Document(
      stableKey: stableKey,
      treeUri: 'content://tree/books',
      documentId: 'id-doc',
      uri: 'content://tree/books/$name',
      displayName: name,
      mimeType: 'application/pdf',
      sizeBytes: 500,
      dateModified: 100,
      relativePath: 'books',
      contentFingerprint: 'fp-doc',
      sourceRevision: 1,
      accessState: DocumentAccessState.accessible,
      firstDiscoveredAt: 1,
      lastDiscoveredAt: 1,
      searchableText: 'untitled machine learning pdf',
    );
  }
}

class _FixedSemanticRepository implements SemanticSearchRepository {
  const _FixedSemanticRepository(this.matches);

  final List<SemanticMatch> matches;

  @override
  Future<List<SemanticMatch>> retrieveSemanticCandidates({
    required List<double> queryVector,
    required String modelId,
    required int dimensions,
    required int maxResults,
    double minSimilarity = SemanticDefaults.minSimilarity,
    required bool includeMedia,
    required bool includeDocuments,
    Set<SemanticContentType>? contentTypes,
    List<String>? mediaCategories,
    bool? isScreenshot,
    List<String>? documentMimeTypes,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  }) async => matches;
}
