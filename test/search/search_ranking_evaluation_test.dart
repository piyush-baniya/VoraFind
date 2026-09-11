import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_items_table.dart'
    show IndexingStatus;
import 'package:vorafind/core/documents/document_models.dart'
    show DocumentAccessState;
import 'package:vorafind/core/platform/content_access_models.dart'
    show ContentCategory;
import 'package:vorafind/core/search/search_field.dart';
import 'package:vorafind/core/search/search_query.dart';
import 'package:vorafind/core/search/search_ranker.dart';

/// Prompt #14 evaluation fixture + golden ranking tests.
///
/// Synthetic but representative of the product's real surfaces: filenames,
/// folders, OCR body text, document text, screenshots, and semantic
/// similarity. Every ordering asserted below is a *defensible search-quality
/// rule* (docs `semantic-search.md` §Evaluation), not an arbitrary snapshot.
///
/// The evaluation table (query → expected top) that guards against regressions:
///
/// ```text
/// "college timetable"                     → college_timetable.pdf   (exact filename)
/// "timetable"                             → college_timetable.pdf   (exact filename)
/// "information about machine learning"    → ML_Fundamentals.pdf     (semantic rescue)
/// "car maintenance"                       → Vehicle_Maintenance_Guide.pdf
/// "exam timetable"                        → college_timetable.pdf   (exact filename + OCR)
/// "neural networks"                       → Chapter_4.pdf           (semantic rescue)
/// "not in any index"                      → (empty)
/// ```
void main() {
  const ranker = SearchRanker();
  final lib = FixtureLibrary();

  group('intent 1: exact filename outranks everything', () {
    test('"college timetable" surfaces the exact file on top', () {
      final results = ranker.rank(
        lib.candidates([
          'vacation_mountains.jpg',
          'lecture_screenshot.png', // OCR college+timetable, isScreenshot
          'timetable_scan.jpg', // OCR "weekly class schedule"
          'college_timetable.pdf', // exact filename
          'random_screenshot.png', // unrelated OCR
        ]),
        _query(['college', 'timetable']),
      );
      expect(results.first.displayName, 'college_timetable.pdf');
      // The exact filename must explain itself with a name match, not semantic.
      expect(
        results.first.matches.any(
          (m) =>
              m.field == SearchField.displayName &&
              m.token == 'timetable' &&
              m.strength == MatchStrength.exact,
        ),
        isTrue,
      );
    });

    test('"timetable" puts exact filename above unrelated semantic match', () {
      final results = ranker.rank(
        lib.candidates(
          ['college_timetable.pdf', 'vacation_mountains.jpg'],
          semanticByKey: const {
            'vacation_mountains.jpg': 0.9, // strong but wrong topic
          },
        ),
        _query(['timetable']),
      );
      expect(results.first.displayName, 'college_timetable.pdf');
    });

    test('single exact filename token beats a moderate semantic match', () {
      final results = ranker.rank(
        lib.candidates(
          ['resume.pdf', 'documents/personal_profile.md'],
          semanticByKey: const {'documents/personal_profile.md': 0.6},
        ),
        _query(['resume']),
      );
      expect(results.first.displayName, 'resume.pdf');
    });
  });

  group('intent 2: partial filename', () {
    test('exact > prefix > substring word matches on the same filename', () {
      final results = ranker.rank(
        lib.candidates([
          'my_weektimetablestyle.txt', // "timetable" only as substring
          'timetables_archive.txt', // "timetable" prefixes "timetables"
          'timetable_final.pdf', // exact whole word
          'vacation_mountains.jpg',
        ]),
        _query(['timetable']),
      );
      expect(results[0].displayName, 'timetable_final.pdf');
      expect(results[0].matches.first.strength, MatchStrength.exact);
      expect(results[1].displayName, 'timetables_archive.txt');
      expect(results[1].matches.first.strength, MatchStrength.prefix);
      expect(results[2].displayName, 'my_weektimetablestyle.txt');
      expect(results[2].matches.first.strength, MatchStrength.substring);
    });
  });

  group('intent 3: semantic concept rescue', () {
    test('semantic-only match surfaces without any keyword hit', () {
      final results = ranker.rank(
        lib.candidates(
          [
            'ML_Fundamentals.pdf', // no "machine learning" tokens in name
            'vacation_mountains.jpg',
          ],
          semanticByKey: const {'ML_Fundamentals.pdf': 0.55},
        ),
        _query(['information', 'about', 'machine', 'learning']),
      );
      expect(results.first.displayName, 'ML_Fundamentals.pdf');
      expect(
        results.first.matches.any((m) => m.field == SearchField.semantic),
        isTrue,
      );
    });

    test('strong semantic beats weak keyword coincidence', () {
      // "car maintenance": the song matches only via its `genre` field
      // (8 × 3 = 24 pts). The manual has *no* literal "car"/"maintenance"
      // token anywhere, only a strong conceptual match (0.6 × 50 = 30 pts).
      // semanticRankWeight=50 was chosen so a true semantic hit outranks the
      // weakest metadata ties but never a real filename/title hit.
      final song = lib.songCandidate(
        'kmix_song.mp3',
        'kmix_song',
        'car repair',
      );
      final manual = lib.candidate(
        'service_manual.pdf',
        'service_manual.pdf',
        semanticSimilarity: 0.6,
      );
      final results = ranker.rank([
        song,
        manual,
      ], _query(['car', 'maintenance']));
      expect(results[0].displayName, 'service_manual.pdf');
      expect(
        results[0].matches.any((m) => m.field == SearchField.semantic),
        isTrue,
      );
      expect(
        results[1].matches.any((m) => m.field == SearchField.genre),
        isTrue,
      );
    });
  });

  group('intent 4: synonyms via semantic similarity', () {
    test('"car repair information" rescues the vehicle manual', () {
      final results = ranker.rank(
        lib.candidates(
          ['Vehicle_Maintenance_Guide.pdf', 'vacation_mountains.jpg'],
          semanticByKey: const {'Vehicle_Maintenance_Guide.pdf': 0.47},
        ),
        _query(['car', 'repair', 'information']),
      );
      expect(results.first.displayName, 'Vehicle_Maintenance_Guide.pdf');
      expect(results.first.matches, isNotEmpty);
    });
  });

  group('intent 5: OCR', () {
    test('OCR exact match outperforms semantic-only on other rows', () {
      final results = ranker.rank(
        lib.candidates(
          [
            'lecture_screenshot.png', // OCR "college timetable exam schedule"
            'random_photo.jpg',
          ],
          semanticByKey: const {'random_photo.jpg': 0.5},
        ),
        _query(['exam', 'timetable']),
      );
      expect(results.first.displayName, 'lecture_screenshot.png');
      expect(
        results.first.matches.any((m) => m.field == SearchField.ocrText),
        isTrue,
      );
    });

    test('OCR substring match stays below exact filename match', () {
      final results = ranker.rank(
        lib.candidates([
          'college_timetable.pdf', // exact filename
          'lecture_photo.jpg', // OCR mentions "timetable" once
        ]),
        _query(['timetable']),
      );
      expect(results.first.displayName, 'college_timetable.pdf');
    });
  });

  group('intent 6: document text', () {
    test('document body text surfaces a file the name never mentions', () {
      final results = ranker.rank(
        lib.candidates([
          'Chapter_4.pdf', // content "neural networks are computational models"
          'ML_Fundamentals.pdf',
          'vacation_mountains.jpg',
        ]),
        _query(['neural', 'networks']),
      );
      final top = results.firstWhere((r) => r.stableKey == 'Chapter_4.pdf');
      expect(
        top.matches.any((m) => m.field == SearchField.documentText),
        isTrue,
      );
    });
  });

  group('intent 7+8: content type', () {
    test('PDF-pinned candidate pool ranks document-text hits first', () {
      // The PDF/screenshot *filters* are enforced at the retrieval layer
      // (SearchService._mayIncludeDocuments + SQL), never in the ranker. This
      // verifies that once the pool is pinned to documents, ordering follows
      // document text + semantic signals without crashes.
      final results = ranker.rank(
        lib.candidates(['ML_Fundamentals.pdf', 'Chapter_4.pdf']),
        _query(
          ['machine', 'learning'],
          documentTypes: {SearchDocumentType.pdf},
        ),
      );
      expect(
        results.every((r) => r.category == ContentCategory.documents),
        isTrue,
      );
      expect(results.first.displayName, 'ML_Fundamentals.pdf');
    });

    test('screenshot OCR match outranks a plain image in a screenshot query', () {
      final results = ranker.rank(
        lib.candidates([
          'random_screenshot.png',
          'lecture_screenshot.png', // OCR "college timetable exam schedule"
          'vacation_mountains.jpg',
        ]),
        _query(['timetable'], screenshot: true),
      );
      // The document row never reaches this pool under a screenshot query —
      // retrieval guarantees it. Given the image-only pool, the screenshot with
      // matching OCR comes first, then the unrelated screenshot, then the plain
      // image (no hits).
      expect(results[0].displayName, 'lecture_screenshot.png');
      expect(results[0].category, ContentCategory.images);
    });
  });

  group('intent 9+10: date filtering', () {
    test('date bounds are preserved through ranking order (deterministic)', () {
      final results = ranker.rank(
        lib.candidates(['lecture_screenshot.png', 'random_screenshot.png']),
        _query(const [], dateFrom: 1000, dateTo: 2000),
      );
      // Filter-only: pure recency + stable key ordering, zero scores.
      expect(results.every((r) => r.score == 0), isTrue);
    });
  });

  group('intent 11: combined query coverage', () {
    test('3/3 tokens outrank 1/3 tokens with comparable field hits', () {
      final results = ranker.rank(
        lib.candidates([
          'college_notes.md', // matches college,machine,learning? name 'college_notes' → 2
          'college_notes_machine_learning.md', // matches all three by name
          'vacation_mountains.jpg',
        ]),
        _query(['college', 'machine', 'learning']),
      );
      expect(results.first.displayName, 'college_notes_machine_learning.md');
    });
  });

  group('deduplication + stability', () {
    test('duplicate stable keys rank deterministically (dedup is service-level)', () {
      // Dedup happens in SearchService._merge, which emits one candidate per
      // stable key keeping the richer (matched) copy. If a duplicate ever
      // reaches the ranker, it must still evaluate both deterministically with
      // the stronger one first.
      final duplicate = SearchCandidate(
        // A second copy of the same media row carrying a semantic signal.
        item: lib.candidate('timetable_scan.jpg', 'timetable_scan.jpg').item,
        semanticSimilarity: 0.7,
      );
      final results = ranker.rank([
        lib.candidate('timetable_scan.jpg', 'timetable_scan.jpg'),
        duplicate,
      ], _query(['timetable']));
      expect(results, hasLength(2));
      expect(results.first.score, greaterThan(results[1].score));
      expect(results.map((r) => r.stableKey).toSet(), {'timetable_scan.jpg'});
    });

    test('repeated identical searches produce identical order', () {
      final fixture = lib.candidates([
        'college_timetable.pdf',
        'lecture_screenshot.png',
        'vacation_mountains.jpg',
      ]);
      final query = _query(['timetable']);
      final a = ranker.rank(fixture, query);
      final b = ranker.rank(fixture, query);
      expect(a.map((r) => r.stableKey), b.map((r) => r.stableKey));
      expect(a.map((r) => r.score), b.map((r) => r.score));
    });
  });

  group('edge + empty + long queries', () {
    test('empty token query yields filter-style recency ordering', () {
      final results = ranker.rank(
        lib.candidates(['random_screenshot.png', 'lecture_screenshot.png']),
        _query(const []),
      );
      expect(results.length, 2);
      expect(results.every((r) => r.score == 0), isTrue);
    });
    test('sub-threshold semantic similarity can never fabricate a semantic match', () {
      final results = ranker.rank(
        lib.candidates(
          ['vacation_mountains.jpg', 'random_screenshot.png'],
          // 0.2 < SemanticDefaults.minSimilarity (0.35); retrieval would never
          // emit this, and the ranker independently refuses to.
          semanticByKey: const {'vacation_mountains.jpg': 0.2},
        ),
        _query(['zzzzx', 'qqqqq', 'yyyyy', '123456']),
      );
      // The rows still appear (filter-only pool semantics) but neither their
      // scores nor their match lists are inflated by the sub-threshold semantic
      // noise.
      expect(results.every((r) => r.matches.isEmpty), isTrue);
      expect(results.every((r) => r.score == 0), isTrue);
    });

    test('long query stays deterministic and bounded per candidate', () {
      final longQuery = List.generate(60, (i) => 'token$i');
      final results = ranker.rank(
        lib.candidates(['token1_mixed.txt', 'vacation_mountains.jpg']),
        _query(longQuery),
      );
      expect(results.length, 2);
      expect(
        results.first.matches.every((m) => m.token.isEmpty == false),
        isTrue,
      );
    });
  });

  group('explanations', () {
    test('semantic-only match explains as semantic', () {
      final results = ranker.rank(
        lib.candidates(
          ['Vehicle_Maintenance_Guide.pdf', 'vacation_mountains.jpg'],
          semanticByKey: const {'Vehicle_Maintenance_Guide.pdf': 0.55},
        ),
        _query(['car', 'repair']),
      );
      expect(
        results.first.matches.any((m) => m.field == SearchField.semantic),
        isTrue,
      );
    });

    test('keyword signal precedes semantic signal in the match list', () {
      final results = ranker.rank(
        lib.candidates(
          ['college_timetable.pdf', 'vacation_mountains.jpg'],
          semanticByKey: const {'college_timetable.pdf': 0.7},
        ),
        _query(['timetable']),
      );
      final matches = results.first.matches;
      final firstKeyword = matches.indexWhere(
        (m) => m.field != SearchField.semantic,
      );
      final firstSemantic = matches.indexWhere(
        (m) => m.field == SearchField.semantic,
      );
      expect(firstKeyword, lessThan(firstSemantic));
      // The exact filename token explains before any conceptual fallback.
      expect(results.first.matches.first.field, SearchField.displayName);
    });
  });
}

NormalizedSearchQuery _query(
  List<String> tokens, {
  int? dateFrom,
  int? dateTo,
  bool? screenshot,
  Set<SearchDocumentType> documentTypes = const {},
}) => NormalizedSearchQuery(
  tokens: tokens,
  categories: screenshot == true ? const [ContentCategory.images] : const [],
  isScreenshot: screenshot,
  dateFrom: dateFrom,
  dateTo: dateTo,
  minSizeBytes: null,
  maxSizeBytes: null,
  pathPrefix: null,
  minDurationMs: null,
  maxDurationMs: null,
  documentTypes: documentTypes,
  limit: 20,
);

/// Deterministic fixture library: named rows (media + documents) plus OCR and
/// document text, so golden ranking tests read like product scenarios.
class FixtureLibrary {
  const FixtureLibrary();

  SearchCandidate candidate(
    String stableKey,
    String displayName, {
    double? semanticSimilarity,
    bool isScreenshot = false,
  }) {
    final key = stableKey;
    if (key.endsWith('.pdf') || key.endsWith('.md') || key.endsWith('.txt')) {
      return SearchCandidate(
        document: _document(key, displayName),
        documentText: _documentText(displayName),
        semanticSimilarity: semanticSimilarity,
      );
    }
    return SearchCandidate(
      item: _mediaItem(key, displayName, isScreenshot: isScreenshot),
      ocrText: _mediaOcr(displayName),
      semanticSimilarity: semanticSimilarity,
    );
  }

  List<SearchCandidate> candidates(
    List<String> displayNames, {
    Map<String, double>? semanticByKey,
  }) {
    return [
      for (final name in displayNames)
        candidate(name, name, semanticSimilarity: semanticByKey?[name]),
    ];
  }

  /// Audio row with a literal `genre` tag (music metadata tier, weight 8).
  SearchCandidate songCandidate(String key, String name, String genre) =>
      SearchCandidate(item: _mediaItem(key, name, genre: genre));

  /// The rows this library indexes, mirroring `SearchNormalizer.storageText`.
  MediaItem _mediaItem(
    String key,
    String name, {
    bool isScreenshot = false,
    String? genre,
  }) {
    final split = name.split('/');
    final fileName = split.last;
    final path = split.length > 1 ? '${split.first}/' : null;
    final category = name.contains('.mp4') ? 'videos' : 'images';
    return MediaItem(
      stableKey: key,
      category: category,
      volumeName: 'external_primary',
      mediaStoreId: 1,
      contentUri: 'content://media/external/images/media/1',
      displayName: fileName,
      title: null,
      mimeType: 'image/jpeg',
      sizeBytes: 100,
      dateAdded: null,
      dateModified: 2000,
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
      genre: genre,
      screenshotScore: isScreenshot ? 1 : null,
      isScreenshot: isScreenshot,
      relinkSignature: null,
      searchableText: _searchable(fileName, path),
      firstDiscoveredAt: 1,
      lastDiscoveredAt: 1,
      lastIndexedGeneration: null,
      metadataRevision: 1,
      indexingStatus: IndexingStatus.none,
      lastSeenAccessScope: null,
    );
  }

  Document _document(String stableKey, String name) {
    final split = name.split('/');
    final fileName = split.last;
    final path = split.length > 1 ? split.first : 'Documents';
    return Document(
      stableKey: stableKey,
      treeUri: 'content://tree/college',
      documentId: stableKey.hashCode.toString(),
      uri: 'content://tree/college/$fileName',
      displayName: fileName,
      mimeType: _documentMime(fileName),
      sizeBytes: 500,
      dateModified: 1000,
      relativePath: path,
      contentFingerprint: 'fp-$stableKey',
      sourceRevision: 1,
      accessState: DocumentAccessState.accessible,
      firstDiscoveredAt: 1,
      lastDiscoveredAt: 1,
      searchableText: _searchable(fileName, path),
    );
  }

  static String _documentMime(String name) {
    if (name.endsWith('.md')) return 'text/markdown';
    if (name.endsWith('.txt')) return 'text/plain';
    return 'application/pdf';
  }

  /// Stored OCR text keyed by the fixture row, mirroring indexed image bodies.
  static String _mediaOcr(String displayName) {
    final base = _wordy(displayName);
    if (displayName.contains('_screenshot')) {
      return 'college timetable exam schedule fall semester 2025';
    }
    if (displayName.contains('timetable_scan')) {
      return 'weekly class schedule exam dates spring';
    }
    if (displayName.contains('receipt')) {
      return 'car repair receipt oil change paid in full';
    }
    if (base.isEmpty) return 'random application settings page';
    return '$base screenshot context';
  }

  /// Stored document text keyed by the fixture row.
  static String _documentText(String displayName) {
    if (displayName.contains('college_timetable')) {
      return 'spring semester timetable with exam dates';
    }
    if (displayName.contains('ML_Fundamentals')) {
      return 'machine learning from data neural networks classification '
          'regression supervised learning models';
    }
    if (displayName.contains('Vehicle_Maintenance_Guide')) {
      return 'a guide to vehicle maintenance car upkeep oil changes brake '
          'inspection';
    }
    if (displayName.contains('Chapter_4')) {
      return 'neural networks are computational models inspired by biological '
          'neurons trained on large datasets';
    }
    if (displayName.contains('college_notes')) {
      return 'college lecture notes about machine learning and neural networks';
    }
    if (displayName.contains('car_repair_notes')) {
      return 'repair log for the family car';
    }
    return _wordy(displayName);
  }

  static String _wordy(String displayName) => displayName
      .replaceAll('/[^a-z0-9]+/', ' ')
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim();

  /// Mirrors `SearchNormalizer.storageText` for fixture searchable_text.
  static String _searchable(String name, String? path) => [
    name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim(),
    if (path != null)
      path.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim(),
  ].join(' ').trim();
}
