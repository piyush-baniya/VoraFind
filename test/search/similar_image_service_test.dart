import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/search/similar_image_service.dart';
import 'package:vorafind/core/visual/image_embedding_provider.dart';
import 'package:vorafind/core/visual/image_pixel_source.dart';
import 'package:vorafind/core/visual/image_visual_models.dart';
import 'package:vorafind/core/visual/image_visual_repository.dart';

import '../database/test_support.dart';

Future<List<double>> _vector(int firstByte) async {
  return const DeterministicImageEmbeddingProvider().embed(
    imageRgbBytes: Uint8List.fromList(List.filled(9, firstByte)),
  );
}

/// Search-side double: canned stored embeddings and canned matches, recording
/// how it was queried.
class _FakeSearchRepository implements ImageVisualSearchRepository {
  final Map<String, List<double>> stored;
  final List<SimilarImageMatch> matches;
  String? lastExclude;
  List<double>? lastReference;

  _FakeSearchRepository({this.stored = const {}, this.matches = const []});

  @override
  Future<StoredImageEmbedding?> getCurrentEmbedding({
    required String stableKey,
    required String modelId,
    required int dimensions,
  }) async {
    final vector = stored[stableKey];
    if (vector == null) return null;
    return StoredImageEmbedding(
      stableKey: stableKey,
      sourceRevision: 1,
      modelId: modelId,
      dimensions: dimensions,
      vector: vector,
    );
  }

  @override
  Future<List<SimilarImageMatch>> findSimilarImages({
    required List<double> referenceVector,
    required String modelId,
    required int dimensions,
    required int maxResults,
    double minSimilarity = ImageVisualDefaults.minSimilarity,
    String? excludeStableKey,
    List<String>? mediaCategories,
    bool? isScreenshot,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  }) async {
    lastReference = referenceVector;
    lastExclude = excludeStableKey;
    return matches;
  }
}

/// Pixel source keyed by first byte + optional failure modes.
class _FakePixelSource implements ImagePixelSource {
  _FakePixelSource({
    this.firstByte = 1,
    this.errorToReturn,
    this.throwDecode = false,
  });

  final int firstByte;
  final String? errorToReturn;
  final bool throwDecode;

  @override
  Future<ImagePixelRead> readImageRgb({
    required String contentUri,
    int dimension = ImageVisualDefaults.inputDimension,
  }) async {
    if (throwDecode) throw StateError('decode exploded');
    if (errorToReturn != null) {
      return ImagePixelRead(
        width: 0,
        height: 0,
        rgbBytes: Uint8List(0),
        errorCode: errorToReturn,
      );
    }
    return ImagePixelRead(
      width: dimension,
      height: dimension,
      rgbBytes: Uint8List.fromList(
        List.filled(dimension * dimension * 3, firstByte),
      ),
    );
  }

  @override
  Future<ImagePixelPng> readImagePng({
    required String contentUri,
    int maxDimension = 384,
  }) async {
    return ImagePixelPng(bytes: Uint8List(0));
  }

  @override
  Future<ImagePixelPick> pickImage() async {
    return const ImagePixelPick(errorCode: ImagePixelError.platformUnavailable);
  }
}

void main() {
  late AppDatabase database;
  late DriftMediaRepository media;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    media = DriftMediaRepository(database);
  });

  tearDown(() => database.close());

  Future<void> insertImages(int count) async {
    for (var i = 1; i <= count; i++) {
      await media.upsert(buildRecord(id: i), nowSeconds: 1000);
    }
  }

  SimilarImageService service({
    required ImageVisualSearchRepository searchRepository,
    ImageEmbeddingProvider provider =
        const DeterministicImageEmbeddingProvider(),
    ImagePixelSource pixelSource = const _FakePixelSourceShim(),
  }) => SimilarImageService(
    searchRepository: searchRepository,
    embeddingProvider: provider,
    pixelSource: pixelSource,
    mediaRepository: media,
  );

  group('SimilarImageService Flow A (indexed reference)', () {
    test('reuses the stored embedding and excludes the reference', () async {
      await insertImages(3);
      final referenceVector = await _vector(1);
      final search = _FakeSearchRepository(
        stored: {'external_primary:1': referenceVector},
        matches: const [
          SimilarImageMatch(stableKey: 'external_primary:2', similarity: 0.92),
          SimilarImageMatch(stableKey: 'external_primary:3', similarity: 0.81),
        ],
      );

      final outcome = await service(searchRepository: search).findSimilar(
        reference: SimilarImageReference(
          stableKey: 'external_primary:1',
          contentUri: 'content://media/external_primary/images/media/1',
          displayName: 'photo_1.jpg',
        ),
      );

      expect(search.lastExclude, 'external_primary:1');
      expect(search.lastReference, referenceVector);
      expect(outcome.results.map((r) => r.stableKey), [
        'external_primary:2',
        'external_primary:3',
      ]);
      expect(outcome.results.first.similarity, 0.92);
      expect(
        outcome.results.first.contentUri,
        'content://media/external_primary/images/media/2',
      );
      expect(outcome.reference.isIndexed, isTrue);
    });

    test('missing stored embedding throws notIndexed', () async {
      await insertImages(1);
      final search = _FakeSearchRepository(stored: const {});

      await expectLater(
        service(searchRepository: search).findSimilar(
          reference: SimilarImageReference(
            stableKey: 'external_primary:1',
            contentUri: 'content://media/external_primary/images/media/1',
            displayName: 'photo_1.jpg',
          ),
        ),
        throwsA(
          isA<SimilarImageException>().having(
            (e) => e.error,
            'error',
            SimilarImageErrorCode.notIndexed,
          ),
        ),
      );
    });

    test(
      'an indexed reference that is also among matches is dropped',
      () async {
        await insertImages(2);
        final referenceVector = await _vector(1);
        final search = _FakeSearchRepository(
          stored: {'external_primary:1': referenceVector},
          matches: [
            SimilarImageMatch(
              stableKey: 'external_primary:1',
              similarity: 0.99,
            ),
            SimilarImageMatch(
              stableKey: 'external_primary:2',
              similarity: 0.70,
            ),
          ],
        );

        final outcome = await service(searchRepository: search).findSimilar(
          reference: SimilarImageReference(
            stableKey: 'external_primary:1',
            contentUri: 'content://media/external_primary/images/media/1',
            displayName: 'photo_1.jpg',
          ),
        );

        expect(outcome.results.map((r) => r.stableKey), ['external_primary:2']);
      },
    );

    test('matches with no media row are never surfaced', () async {
      await insertImages(1);
      final referenceVector = await _vector(1);
      final search = _FakeSearchRepository(
        stored: {'external_primary:1': referenceVector},
        matches: const [
          SimilarImageMatch(stableKey: 'external_primary:99', similarity: 0.9),
        ],
      );

      final outcome = await service(searchRepository: search).findSimilar(
        reference: SimilarImageReference(
          stableKey: 'external_primary:1',
          contentUri: 'content://media/external_primary/images/media/1',
          displayName: 'photo_1.jpg',
        ),
      );

      expect(outcome.isEmpty, isTrue);
    });
  });

  group('SimilarImageService Flow B (picked reference)', () {
    test('decodes, embeds ephemerally, and returns shaped results', () async {
      await insertImages(2);
      final search = _FakeSearchRepository(
        matches: const [
          SimilarImageMatch(stableKey: 'external_primary:1', similarity: 0.88),
          SimilarImageMatch(stableKey: 'external_primary:2', similarity: 0.75),
        ],
      );

      final outcome =
          await service(
            searchRepository: search,
            pixelSource: _FakePixelSource(firstByte: 5),
          ).findSimilar(
            reference: const SimilarImageReference(
              contentUri: 'content://picked/1',
              displayName: 'Selected image',
            ),
          );

      expect(outcome.reference.isIndexed, isFalse);
      expect(search.lastExclude, isNull);
      expect(search.lastReference, await _vector(5));
      expect(outcome.results.map((r) => r.stableKey), [
        'external_primary:1',
        'external_primary:2',
      ]);
    });

    test('corrupt read maps to decodeFailed', () async {
      await insertImages(1);
      final search = _FakeSearchRepository();

      await expectLater(
        service(
          searchRepository: search,
          pixelSource: _FakePixelSource(errorToReturn: ImagePixelError.corrupt),
        ).findSimilar(
          reference: const SimilarImageReference(
            contentUri: 'content://picked/1',
            displayName: 'Selected image',
          ),
        ),
        throwsA(
          isA<SimilarImageException>().having(
            (e) => e.error,
            'error',
            SimilarImageErrorCode.decodeFailed,
          ),
        ),
      );
    });

    test('platform-unavailable read maps to unavailable', () async {
      await insertImages(1);
      final search = _FakeSearchRepository();

      await expectLater(
        service(
          searchRepository: search,
          pixelSource: _FakePixelSource(
            errorToReturn: ImagePixelError.platformUnavailable,
          ),
        ).findSimilar(
          reference: const SimilarImageReference(
            contentUri: 'content://picked/1',
            displayName: 'Selected image',
          ),
        ),
        throwsA(
          isA<SimilarImageException>().having(
            (e) => e.error,
            'error',
            SimilarImageErrorCode.unavailable,
          ),
        ),
      );
    });

    test('a throwing decode is treated as failure, not a crash', () async {
      await insertImages(1);
      final search = _FakeSearchRepository();

      await expectLater(
        service(
          searchRepository: search,
          pixelSource: _FakePixelSource(throwDecode: true),
        ).findSimilar(
          reference: const SimilarImageReference(
            contentUri: 'content://picked/1',
            displayName: 'Selected image',
          ),
        ),
        throwsA(
          isA<SimilarImageException>().having(
            (e) => e.error,
            'error',
            SimilarImageErrorCode.failed,
          ),
        ),
      );
    });

    test('unavailable embedding provider maps to unavailable', () async {
      await insertImages(1);
      final search = _FakeSearchRepository();

      await expectLater(
        service(
          searchRepository: search,
          provider: const UnavailableImageEmbeddingProvider(),
        ).findSimilar(
          reference: const SimilarImageReference(
            contentUri: 'content://picked/1',
            displayName: 'Selected image',
          ),
        ),
        throwsA(
          isA<SimilarImageException>().having(
            (e) => e.error,
            'error',
            SimilarImageErrorCode.unavailable,
          ),
        ),
      );
    });

    test('invalid input embedding maps to decodeFailed', () async {
      await insertImages(1);
      final search = _FakeSearchRepository();
      const throwing = _ThrowingProvider(ImageVisualErrorCode.invalidInput);

      await expectLater(
        service(searchRepository: search, provider: throwing).findSimilar(
          reference: const SimilarImageReference(
            contentUri: 'content://picked/1',
            displayName: 'Selected image',
          ),
        ),
        throwsA(
          isA<SimilarImageException>().having(
            (e) => e.error,
            'error',
            SimilarImageErrorCode.decodeFailed,
          ),
        ),
      );
    });

    test('empty candidate set returns an empty outcome', () async {
      await insertImages(1);
      final search = _FakeSearchRepository();

      final outcome = await service(searchRepository: search).findSimilar(
        reference: const SimilarImageReference(
          contentUri: 'content://picked/1',
          displayName: 'Selected image',
        ),
      );

      expect(outcome.isEmpty, isTrue);
      expect(outcome.results, isEmpty);
    });
  });
}

class _FakePixelSourceShim implements ImagePixelSource {
  const _FakePixelSourceShim();

  @override
  Future<ImagePixelRead> readImageRgb({
    required String contentUri,
    int dimension = ImageVisualDefaults.inputDimension,
  }) async {
    return ImagePixelRead(
      width: dimension,
      height: dimension,
      rgbBytes: Uint8List.fromList(List.filled(dimension * dimension * 3, 1)),
    );
  }

  @override
  Future<ImagePixelPng> readImagePng({
    required String contentUri,
    int maxDimension = 384,
  }) async {
    return ImagePixelPng(bytes: Uint8List(0));
  }

  @override
  Future<ImagePixelPick> pickImage() async {
    return const ImagePixelPick(errorCode: ImagePixelError.platformUnavailable);
  }
}

class _ThrowingProvider implements ImageEmbeddingProvider {
  const _ThrowingProvider(this.code);

  final ImageVisualErrorCode code;

  @override
  bool get isAvailable => true;
  @override
  int get dimensions => ImageVisualDefaults.dimensions;
  @override
  String get modelId => 'throwing';

  @override
  Future<List<double>> embed({required Uint8List imageRgbBytes}) async {
    throw ImageEmbeddingException(code);
  }

  @override
  Future<void> dispose() async {}
}
