import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_items_table.dart'
    show IndexingStatus;
import 'package:vorafind/core/search/search_field.dart';
import 'package:vorafind/core/search/search_query.dart';
import 'package:vorafind/core/search/search_ranker.dart';

void main() {
  const scorer = SearchScorer();

  group('SearchScorer', () {
    test('filename matches beat path matches', () {
      final byName = scorer.score(
        displayName: 'citizenship_front.jpg',
        tokens: ['citizenship'],
      );
      final byPath = scorer.score(
        displayName: 'photo.jpg',
        relativePath: 'Documents/citizenship/',
        tokens: ['citizenship'],
      );
      expect(byName.score, greaterThan(byPath.score));
    });

    test('exact word match beats substring match', () {
      final exact = scorer.score(
        displayName: 'citizenship.jpg',
        tokens: ['citizenship'],
      );
      final substring = scorer.score(
        displayName: 'anticitizenshiptional.jpg',
        tokens: ['citizenship'],
      );
      expect(exact.score, greaterThan(substring.score));
      expect(exact.matches.single.strength, MatchStrength.exact);
      expect(substring.matches.single.strength, MatchStrength.substring);
    });

    test('prefix match beats substring match', () {
      final prefix = scorer.score(
        displayName: 'citizenship_front.jpg',
        tokens: ['citizen'],
      );
      final substring = scorer.score(
        displayName: 'anticitizenshiptional.jpg',
        tokens: ['citizenship'],
      );
      expect(prefix.matches.single.strength, MatchStrength.prefix);
      expect(substring.matches.single.strength, MatchStrength.substring);
      expect(prefix.score, greaterThan(substring.score));
    });

    test('coverage bonus rewards matching more tokens', () {
      final one = scorer.score(
        displayName: 'flutter.pdf',
        tokens: ['flutter', 'notes'],
      );
      final three = scorer.score(
        displayName: 'flutter notes v2.pdf',
        tokens: ['flutter', 'notes', 'v2'],
      );
      expect(three.score, greaterThan(one.score));
    });

    test('non-matching tokens produce no match info', () {
      final result = scorer.score(displayName: 'photo.jpg', tokens: ['zebra']);
      expect(result.score, 0);
      expect(result.matches, isEmpty);
    });

    test('ocr text matches are scored through SearchField.ocrText', () {
      final result = scorer.score(
        displayName: 'photo.jpg',
        ocrText: 'lorem ipsum 55x50 note',
        tokens: ['x50'],
      );
      expect(result.score, greaterThan(0));
      expect(result.matches.single.field, SearchField.ocrText);
      expect(result.matches.single.strength, MatchStrength.substring);
    });
  });

  group('SearchRanker.rank', () {
    test('sorts by score then recency then stable key deterministically', () {
      const ranker = SearchRanker();
      final rows = [
        _candidate(key: 'a', name: 'photo.jpg', date: 100),
        _candidate(key: 'b', name: 'citizenship_front.jpg', date: 200),
        _candidate(key: 'c', name: 'citizenship_back.jpg', date: 200),
      ];

      final results = ranker.rank(rows, _queryFor(['citizenship']));
      expect(results.map((r) => r.stableKey), ['b', 'c', 'a']);
    });

    test('ties break by stable key ascending', () {
      const ranker = SearchRanker();
      final results = ranker.rank([
        _candidate(key: 'z', name: 'same.jpg', date: 300),
        _candidate(key: 'a', name: 'same.jpg', date: 300),
      ], _queryFor(['same']));
      expect(results.map((r) => r.stableKey), ['a', 'z']);
    });

    test('respects the result limit', () {
      const ranker = SearchRanker();
      final rows = List.generate(
        10,
        (i) => _candidate(key: 'k$i', name: 'citizen_$i.jpg', date: 100 + i),
      );
      final results = ranker.rank(rows, _queryFor(['citizen'], limit: 3));
      expect(results, hasLength(3));
    });

    test('returns the top-ranked subset of the bounded pool', () {
      const ranker = SearchRanker();
      final rows = [
        _candidate(key: 'path', name: 'photo.jpg', path: 'Folder/citizenship/'),
        _candidate(key: 'name', name: 'citizenship.jpg'),
      ];
      final results = ranker.rank(rows, _queryFor(['citizenship']));
      expect(results.first.stableKey, 'name');
      expect(results.first.score, greaterThan(results.last.score));
    });

    test('OCR body text can surface a row its filename never mentions', () {
      const ranker = SearchRanker();
      final rows = [
        _candidate(
          key: 'ocr',
          name: 'IMG_0001.jpg',
          ocrText: 'hospital discharge vora 5550 summary',
        ),
        _candidate(key: 'other', name: 'vacation.jpg'),
      ];
      final results = ranker.rank(rows, _queryFor(['5550']));
      expect(results.first.stableKey, 'ocr');
      expect(results.first.matches.single.field, SearchField.ocrText);
    });

    test('filter-only search keeps recency order with zero scores', () {
      const ranker = SearchRanker();
      final results = ranker.rank([
        _candidate(key: 'old', name: 'a.jpg', date: 100),
        _candidate(key: 'new', name: 'b.jpg', date: 900),
      ], _queryFor(const []));
      expect(results.first.stableKey, 'new');
      expect(results.every((r) => r.score == 0), isTrue);
    });
  });
}

NormalizedSearchQuery _queryFor(List<String> tokens, {int limit = 20}) =>
    NormalizedSearchQuery(
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
      limit: limit,
    );

SearchCandidate _candidate({
  required String key,
  required String name,
  int? date,
  String? path,
  String? ocrText,
}) => SearchCandidate(
  item: _mediaItem(key: key, name: name, date: date, path: path),
  ocrText: ocrText,
);

MediaItem _mediaItem({
  required String key,
  required String name,
  int? date,
  String? path,
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
  relativePath: path,
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
  searchableText: _searchable(name, path),
  firstDiscoveredAt: 1,
  lastDiscoveredAt: 1,
  lastIndexedGeneration: null,
  metadataRevision: 1,
  indexingStatus: IndexingStatus.none,
  lastSeenAccessScope: null,
);

/// Mirrors `SearchNormalizer.storageText` for fixture searchable_text values.
String _searchable(String name, String? path) => [
  name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim(),
  if (path != null)
    path.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim(),
].join(' ').trim();
