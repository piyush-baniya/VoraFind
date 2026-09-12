import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/semantic/vector_math.dart';
import 'package:vorafind/core/visual/drift_image_visual_repository.dart';
import 'package:vorafind/core/visual/image_embedding_provider.dart';
import 'package:vorafind/core/visual/image_pixel_source.dart';
import 'package:vorafind/core/visual/image_visual_index_coordinator.dart';
import 'package:vorafind/core/visual/image_visual_models.dart';

import '../database/test_support.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

Uint8List _rgb(
  int firstByte, {
  int dimension = ImageVisualDefaults.inputDimension,
}) {
  final bytes = Uint8List(dimension * dimension * 3);
  bytes.fillRange(0, bytes.length, firstByte);
  return bytes;
}

/// Unit vector with a single hot dimension selected by [firstByte].
Future<List<double>> _vector(int firstByte) async {
  return const DeterministicImageEmbeddingProvider().embed(
    imageRgbBytes: _rgb(firstByte),
  );
}

String _key(int id) => 'external_primary:$id';

/// Content URI derived exactly like `buildRecord`.
String _uri(int id) => 'content://media/external_primary/images/media/$id';

Future<void> _insertImage(
  DriftMediaRepository media, {
  required int id,
  bool? isScreenshot,
  String? relativePath,
  int? dateModified,
}) async {
  await media.upsert(
    buildRecord(
      id: id,
      isScreenshot: isScreenshot,
      relativePath: relativePath,
      dateModified: dateModified,
    ),
    nowSeconds: 1000,
  );
}

/// Deterministic pixel source whose reads are keyed by content URI.
class _FakePixelSource implements ImagePixelSource {
  _FakePixelSource({
    this.fills = const <String, int>{},
    this.failKeys = const <String>{},
    this.throwKeys = const <String>{},
  });

  /// contentUri → first RGB byte (controls the deterministic embedding).
  final Map<String, int> fills;
  final Set<String> failKeys;
  final Set<String> throwKeys;

  @override
  Future<ImagePixelRead> readImageRgb({
    required String contentUri,
    int dimension = ImageVisualDefaults.inputDimension,
  }) async {
    if (throwKeys.contains(contentUri)) {
      throw StateError('platform decode exploded');
    }
    if (failKeys.contains(contentUri)) {
      return ImagePixelRead(
        width: 0,
        height: 0,
        rgbBytes: Uint8List(0),
        errorCode: ImagePixelError.corrupt,
      );
    }
    final size = dimension * dimension * 3;
    final bytes = Uint8List(size);
    bytes.fillRange(0, bytes.length, fills[contentUri] ?? 7);
    return ImagePixelRead(width: dimension, height: dimension, rgbBytes: bytes);
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
  group('DriftImageVisualRepository persistence', () {
    late AppDatabase database;
    late DriftMediaRepository media;
    late DriftImageVisualRepository repository;

    setUp(() {
      database = _db();
      media = DriftMediaRepository(database);
      repository = DriftImageVisualRepository(database);
    });
    tearDown(() => database.close());

    test('saveEmbedding persists status, vector, and dimensions', () async {
      await _insertImage(media, id: 1);
      final vector = await _vector(1);
      await repository.saveEmbedding(
        stableKey: _key(1),
        sourceRevision: 1,
        modelId: 'im1',
        vector: vector,
        nowEpochSeconds: 2000,
      );

      expect(await repository.getStatus(_key(1)), ImageVisualStatus.completed);
      final stored = await repository.getCurrentEmbedding(
        stableKey: _key(1),
        modelId: 'im1',
        dimensions: 1280,
      );
      expect(stored, isNotNull);
      expect(stored!.vector.length, 1280);
      expect(VectorMath.cosine(stored.vector, vector), closeTo(1.0, 1e-9));
      final stats = await repository.stats();
      expect(stats.total, 1);
      expect(stats.completed, 1);
    });

    test(
      'saveFailure persists permanent unsupported and transient failed',
      () async {
        await _insertImage(media, id: 1);
        await _insertImage(media, id: 2);
        await repository.saveFailure(
          stableKey: _key(1),
          sourceRevision: 1,
          modelId: 'im1',
          errorCode: 'invalidInput',
          nowEpochSeconds: 2000,
          permanent: true,
        );
        await repository.saveFailure(
          stableKey: _key(2),
          sourceRevision: 1,
          modelId: 'im1',
          errorCode: 'failed',
          nowEpochSeconds: 2000,
          permanent: false,
        );

        expect(
          await repository.getStatus(_key(1)),
          ImageVisualStatus.unsupported,
        );
        expect(await repository.getStatus(_key(2)), ImageVisualStatus.failed);
        final stats = await repository.stats();
        expect(stats.unsupported, 1);
        expect(stats.failed, 1);
      },
    );

    test('clear removes every embedding row', () async {
      await _insertImage(media, id: 1);
      await repository.saveEmbedding(
        stableKey: _key(1),
        sourceRevision: 1,
        modelId: 'im1',
        vector: await _vector(1),
        nowEpochSeconds: 2000,
      );
      await repository.clear();
      expect((await repository.stats()).total, 0);
    });
  });

  group('DriftImageVisualRepository eligibility', () {
    late AppDatabase database;
    late DriftMediaRepository media;
    late DriftImageVisualRepository repository;

    setUp(() {
      database = _db();
      media = DriftMediaRepository(database);
      repository = DriftImageVisualRepository(database);
    });
    tearDown(() => database.close());

    test(
      'missing rows are candidates, bounded by batchSize and only images',
      () async {
        for (var i = 1; i <= 3; i++) {
          await _insertImage(media, id: i);
        }
        await _insertImage(media, id: 4);
        final candidates = await repository.findImageVisualCandidates(
          batchSize: 2,
          modelId: 'im1',
          nowEpochSeconds: 5000,
        );
        expect(candidates, hasLength(2));
        expect(candidates.map((c) => c.stableKey), [_key(1), _key(2)]);
      },
    );

    test('current completed rows are not re-embedded', () async {
      await _insertImage(media, id: 1);
      await repository.saveEmbedding(
        stableKey: _key(1),
        sourceRevision: 1,
        modelId: 'im1',
        vector: await _vector(1),
        nowEpochSeconds: 2000,
      );
      final candidates = await repository.findImageVisualCandidates(
        batchSize: 10,
        modelId: 'im1',
        nowEpochSeconds: 5000,
      );
      expect(candidates, isEmpty);
    });

    test('stale revision or stale model id re-queues completed rows', () async {
      await _insertImage(media, id: 1);
      await repository.saveEmbedding(
        stableKey: _key(1),
        sourceRevision: 1,
        modelId: 'im1',
        vector: await _vector(1),
        nowEpochSeconds: 2000,
      );

      await (database.update(database.mediaItems)
            ..where((m) => m.stableKey.equals(_key(1))))
          .write(const MediaItemsCompanion(metadataRevision: Value(3)));
      var candidates = await repository.findImageVisualCandidates(
        batchSize: 10,
        modelId: 'im1',
        nowEpochSeconds: 5000,
      );
      expect(candidates, hasLength(1));

      await repository.saveEmbedding(
        stableKey: _key(1),
        sourceRevision: 3,
        modelId: 'im1',
        vector: await _vector(1),
        nowEpochSeconds: 3000,
      );
      candidates = await repository.findImageVisualCandidates(
        batchSize: 10,
        modelId: 'im2',
        nowEpochSeconds: 5000,
      );
      expect(candidates, hasLength(1));
    });

    test('failed rows retry only after the cooldown', () async {
      await _insertImage(media, id: 1);
      await repository.saveFailure(
        stableKey: _key(1),
        sourceRevision: 1,
        modelId: 'im1',
        errorCode: 'failed',
        nowEpochSeconds: 2000,
        permanent: false,
      );

      var candidates = await repository.findImageVisualCandidates(
        batchSize: 10,
        modelId: 'im1',
        nowEpochSeconds: 3000,
        retryCooldownSeconds: 3600,
      );
      expect(candidates, isEmpty);

      candidates = await repository.findImageVisualCandidates(
        batchSize: 10,
        modelId: 'im1',
        nowEpochSeconds: 2000 + 3600,
        retryCooldownSeconds: 3600,
      );
      expect(candidates, hasLength(1));
    });

    test('unsupported rows never retry', () async {
      await _insertImage(media, id: 1);
      await repository.saveFailure(
        stableKey: _key(1),
        sourceRevision: 1,
        modelId: 'im1',
        errorCode: 'invalidInput',
        nowEpochSeconds: 2000,
        permanent: true,
      );
      final candidates = await repository.findImageVisualCandidates(
        batchSize: 10,
        modelId: 'im1',
        nowEpochSeconds: 2000 + 3600,
        retryCooldownSeconds: 3600,
      );
      expect(candidates, isEmpty);
    });
  });

  group('DriftImageVisualRepository retrieval', () {
    late AppDatabase database;
    late DriftMediaRepository media;
    late DriftImageVisualRepository repository;

    setUp(() {
      database = _db();
      media = DriftMediaRepository(database);
      repository = DriftImageVisualRepository(database);
    });
    tearDown(() => database.close());

    Future<void> seed(int id, int firstByte) async {
      await _insertImage(media, id: id);
      await repository.saveEmbedding(
        stableKey: _key(id),
        sourceRevision: 1,
        modelId: 'im1',
        vector: await _vector(firstByte),
        nowEpochSeconds: 2000,
      );
    }

    test('returns top-K by cosine with deterministic tie-break', () async {
      await seed(1, 1);
      await seed(2, 2); // orthogonal to 1 → below minSimilarity.
      await seed(3, 1); // identical to 1 → tie-break by stableKey asc.

      final reference = await _vector(1);
      final matches = await repository.findSimilarImages(
        referenceVector: reference,
        modelId: 'im1',
        dimensions: 1280,
        maxResults: 10,
      );
      expect(matches.map((m) => m.stableKey), [_key(1), _key(3)]);
      expect(matches.every((m) => m.similarity >= 0.99), isTrue);
    });

    test('maxResults caps the returned pool', () async {
      await seed(1, 1);
      await seed(3, 1);
      final matches = await repository.findSimilarImages(
        referenceVector: await _vector(1),
        modelId: 'im1',
        dimensions: 1280,
        maxResults: 1,
      );
      expect(matches.map((m) => m.stableKey), [_key(1)]);
    });

    test('excludeStableKey removes the reference row', () async {
      await seed(1, 1);
      await seed(3, 1);
      final matches = await repository.findSimilarImages(
        referenceVector: await _vector(1),
        modelId: 'im1',
        dimensions: 1280,
        maxResults: 10,
        excludeStableKey: _key(1),
      );
      expect(matches.map((m) => m.stableKey), [_key(3)]);
    });

    test('minSimilarity excludes weak matches at the boundary', () async {
      await seed(1, 1);
      await seed(2, 2);
      // Orthogonal matches are excluded at the default floor…
      expect(
        await repository.findSimilarImages(
          referenceVector: await _vector(1),
          modelId: 'im1',
          dimensions: 1280,
          maxResults: 10,
        ),
        hasLength(1),
      );
      // …and re-admitted when the caller lowers the floor explicitly.
      expect(
        await repository.findSimilarImages(
          referenceVector: await _vector(1),
          modelId: 'im1',
          dimensions: 1280,
          maxResults: 10,
          minSimilarity: 0,
        ),
        hasLength(2),
      );
    });

    test('media filters apply in SQL before ranking', () async {
      await _insertImage(media, id: 1, isScreenshot: true, dateModified: 1000);
      await repository.saveEmbedding(
        stableKey: _key(1),
        sourceRevision: 1,
        modelId: 'im1',
        vector: await _vector(1),
        nowEpochSeconds: 2000,
      );
      await _insertImage(
        media,
        id: 2,
        isScreenshot: false,
        relativePath: 'Pictures/Screenshots/',
        dateModified: 9000,
      );
      await repository.saveEmbedding(
        stableKey: _key(2),
        sourceRevision: 1,
        modelId: 'im1',
        vector: await _vector(1),
        nowEpochSeconds: 2000,
      );

      final reference = await _vector(1);
      Future<List<SimilarImageMatch>> query({
        bool? isScreenshot,
        int? dateFrom,
        int? dateTo,
        String? pathPrefix,
      }) => repository.findSimilarImages(
        referenceVector: reference,
        modelId: 'im1',
        dimensions: 1280,
        maxResults: 10,
        isScreenshot: isScreenshot,
        dateFrom: dateFrom,
        dateTo: dateTo,
        pathPrefix: pathPrefix,
      );

      expect((await query(isScreenshot: false)).map((m) => m.stableKey), [
        _key(2),
      ]);
      expect((await query(dateFrom: 5000)).map((m) => m.stableKey), [_key(2)]);
      expect((await query(dateTo: 5000)).map((m) => m.stableKey), [_key(1)]);
      expect((await query(pathPrefix: 'Pictures/')).map((m) => m.stableKey), [
        _key(2),
      ]);
    });

    test('malformed rows are skipped, never thrown', () async {
      await seed(1, 1);
      // Hand-write a row whose vector bytes cannot be decoded (truncated).
      await database
          .into(database.imageVisualEmbeddings)
          .insert(
            ImageVisualEmbeddingsCompanion.insert(
              stableKey: _key(2),
              sourceRevision: 1,
              modelId: 'im1',
              dimensions: 1280,
              embeddingData: Value(Uint8List.fromList(List.filled(3, 0))),
              quantization: const Value('f32'),
              status: 'completed',
              createdAt: 2000,
              updatedAt: 2000,
            ),
          );
      final matches = await repository.findSimilarImages(
        referenceVector: await _vector(1),
        modelId: 'im1',
        dimensions: 1280,
        maxResults: 10,
      );
      expect(matches.map((m) => m.stableKey), [_key(1)]);
    });

    test('other models and dimensions cannot cross the boundary', () async {
      await seed(1, 1);
      expect(
        await repository.findSimilarImages(
          referenceVector: await _vector(1),
          modelId: 'other',
          dimensions: 1280,
          maxResults: 10,
        ),
        isEmpty,
      );
      expect(
        await repository.getCurrentEmbedding(
          stableKey: _key(1),
          modelId: 'other',
          dimensions: 1280,
        ),
        isNull,
      );
      expect(
        await repository.getCurrentEmbedding(
          stableKey: _key(1),
          modelId: 'im1',
          dimensions: 512,
        ),
        isNull,
      );
    });
  });

  group('ImageVisualIndexCoordinator', () {
    late AppDatabase database;
    late DriftMediaRepository media;
    late DriftImageVisualRepository repository;

    setUp(() {
      database = _db();
      media = DriftMediaRepository(database);
      repository = DriftImageVisualRepository(database);
    });
    tearDown(() => database.close());

    Future<void> seedImages(int count) async {
      for (var i = 1; i <= count; i++) {
        await _insertImage(media, id: i);
      }
    }

    ImageVisualIndexCoordinator coordinator({
      required ImagePixelSource pixelSource,
      ImageEmbeddingProvider provider =
          const DeterministicImageEmbeddingProvider(),
      int batchSize = 2,
    }) => ImageVisualIndexCoordinator(
      provider: provider,
      pixelSource: pixelSource,
      repository: repository,
      batchSize: batchSize,
    );

    Future<ImageVisualRunProgress> last(ImageVisualIndexCoordinator c) async {
      ImageVisualRunProgress current = const ImageVisualRunProgress(
        status: ImageVisualRunStatus.completed,
        processed: 0,
        total: 0,
        succeeded: 0,
        failed: 0,
      );
      await for (final event in c.run()) {
        current = event;
      }
      return current;
    }

    test(
      'unavailable provider short-circuits without touching the store',
      () async {
        await seedImages(1);
        final events = await last(
          coordinator(
            pixelSource: _FakePixelSource(),
            provider: const UnavailableImageEmbeddingProvider(),
          ),
        );
        expect(events.status, ImageVisualRunStatus.unavailable);
        expect(await repository.getStatus(_key(1)), isNull);
      },
    );

    test('successful run persists embeddings and completes', () async {
      await seedImages(3);
      final events = await last(
        coordinator(
          pixelSource: _FakePixelSource(fills: {_uri(1): 1}),
          batchSize: 2,
        ),
      );

      expect(events.status, ImageVisualRunStatus.completed);
      expect(events.processed, 3);
      expect(events.succeeded, 3);
      expect(events.failed, 0);
      final stats = await repository.stats();
      expect(stats.completed, 3);
      final stored = await repository.getCurrentEmbedding(
        stableKey: _key(1),
        modelId: const DeterministicImageEmbeddingProvider().modelId,
        dimensions: 1280,
      );
      expect(stored, isNotNull);
      expect(stored!.vector.length, 1280);
    });

    test(
      'per-image failure isolation: one bad image does not stop the run',
      () async {
        await seedImages(3);
        final events = await last(
          coordinator(
            pixelSource: _FakePixelSource(
              failKeys: {_uri(2)},
              fills: {_uri(1): 1, _uri(3): 3},
            ),
          ),
        );

        expect(events.status, ImageVisualRunStatus.completed);
        expect(events.succeeded, 2);
        expect(events.failed, 1);
        expect(
          await repository.getStatus(_key(2)),
          ImageVisualStatus.unsupported,
        );
      },
    );

    test('a throwing platform read is recorded, not fatal', () async {
      await seedImages(2);
      final events = await last(
        coordinator(pixelSource: _FakePixelSource(throwKeys: {_uri(1)})),
      );

      expect(events.status, ImageVisualRunStatus.completed);
      expect(events.succeeded, 1);
      expect(events.failed, 1);
      expect(await repository.getStatus(_key(1)), ImageVisualStatus.failed);
    });

    test('zero-size reads are terminal unsupported', () async {
      await seedImages(1);
      final events = await last(
        coordinator(pixelSource: _DegeneratePixelSource()),
      );

      expect(events.status, ImageVisualRunStatus.completed);
      expect(events.succeeded, 0);
      expect(events.failed, 1);
      expect(
        await repository.getStatus(_key(1)),
        ImageVisualStatus.unsupported,
      );
    });

    test('cancellation stops between batches and keeps prior work', () async {
      await seedImages(3);
      final c = coordinator(
        pixelSource: _FakePixelSource(fills: {_uri(1): 1, _uri(2): 2}),
      );
      ImageVisualRunProgress current = const ImageVisualRunProgress(
        status: ImageVisualRunStatus.running,
        processed: 0,
        total: 0,
        succeeded: 0,
        failed: 0,
      );
      await for (final event in c.run()) {
        current = event;
        if (event.processed >= 2) c.cancel();
      }
      expect(current.status, ImageVisualRunStatus.cancelled);
      expect(await repository.getStatus(_key(1)), ImageVisualStatus.completed);
      expect(await repository.getStatus(_key(2)), ImageVisualStatus.completed);
      expect(await repository.getStatus(_key(3)), isNull);
    });

    test(
      'resumability: a cancelled run picks up the remaining queue',
      () async {
        await seedImages(3);
        final first = coordinator(
          pixelSource: _FakePixelSource(fills: {_uri(1): 1}),
        );
        await for (final event in first.run()) {
          if (event.processed >= 2) first.cancel();
        }
        final second = coordinator(
          pixelSource: _FakePixelSource(fills: {_uri(3): 3}),
        );
        final events = await last(second);
        expect(events.status, ImageVisualRunStatus.completed);
        expect(
          await repository.getStatus(_key(3)),
          ImageVisualStatus.completed,
        );
      },
    );
  });

  group('ImagePixelSource method channel', () {
    test('parses reads and survives a missing plugin', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final channel = const MethodChannel('vorafind/image');
      final source = MethodChannelImagePixelSource(channel: channel);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      final rgb = Uint8List.fromList(List.filled(36, 9));
      messenger.setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'readImageRgb' => {'width': 2, 'height': 2, 'rgb': rgb},
          'readImagePng' => {'bytes': Uint8List.fromList(List.filled(4, 1))},
          'pickImage' => {'uri': 'content://picked/1'},
          _ => throw UnimplementedError(),
        };
      });

      final read = await source.readImageRgb(contentUri: 'content://x');
      expect(read.errorCode, isNull);
      expect(read.width, 2);
      expect(read.height, 2);
      expect(read.rgbBytes, rgb);

      final png = await source.readImagePng(contentUri: 'content://x');
      expect(png.errorCode, isNull);
      expect(png.bytes, hasLength(4));

      final pick = await source.pickImage();
      expect(pick.errorCode, isNull);
      expect(pick.contentUri, 'content://picked/1');

      messenger.setMockMethodCallHandler(channel, null);
      expect(
        (await source.readImageRgb(contentUri: 'content://x')).errorCode,
        ImagePixelError.platformUnavailable,
      );
      expect(
        (await source.readImagePng(contentUri: 'content://x')).errorCode,
        ImagePixelError.platformUnavailable,
      );
      expect(
        (await source.pickImage()).errorCode,
        ImagePixelError.platformUnavailable,
      );
    });

    test('PlatformException codes surface as error codes', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final channel = const MethodChannel('vorafind/image');
      final source = MethodChannelImagePixelSource(channel: channel);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'corrupt');
      });
      expect(
        (await source.readImageRgb(contentUri: 'content://x')).errorCode,
        'corrupt',
      );
      messenger.setMockMethodCallHandler(channel, null);
    });
  });

  group('DeterministicImageEmbeddingProvider', () {
    test('is deterministic, bounded, and available', () async {
      const provider = DeterministicImageEmbeddingProvider();
      expect(provider.isAvailable, isTrue);
      expect(provider.dimensions, 1280);
      expect(provider.modelId, 'deterministic-image-1280');

      final a = await provider.embed(imageRgbBytes: _rgb(5));
      final b = await provider.embed(imageRgbBytes: _rgb(5));
      expect(a, b);
      expect(VectorMath.cosine(a, b), closeTo(1.0, 1e-9));
      expect(
        VectorMath.cosine(a, await provider.embed(imageRgbBytes: _rgb(6))),
        lessThan(1e-9),
      );
      expect(a, hasLength(1280));
      expect(a.any((v) => v.isNaN || v.isInfinite), isFalse);
      expect(await provider.embed(imageRgbBytes: Uint8List(0)), _zeroVector);
    });
  });
}

bool _zeroVector(List<double> v) => v.every((x) => x == 0);

/// Returns a zero-size read so the coordinator's shape validation runs.
class _DegeneratePixelSource implements ImagePixelSource {
  @override
  Future<ImagePixelRead> readImageRgb({
    required String contentUri,
    int dimension = ImageVisualDefaults.inputDimension,
  }) async {
    return ImagePixelRead(width: 0, height: 0, rgbBytes: Uint8List(0));
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
