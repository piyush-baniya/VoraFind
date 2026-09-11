import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/search/search_query.dart';
import 'package:vorafind/core/search/search_result.dart';
import 'package:vorafind/core/search/search_service.dart';
import 'package:vorafind/core/visual/drift_visual_repository.dart';
import 'package:vorafind/core/visual/video_frame_sampler.dart';
import 'package:vorafind/core/visual/visual_frame_classifier.dart';
import 'package:vorafind/core/visual/visual_index_coordinator.dart';
import 'package:vorafind/core/visual/visual_models.dart';
import 'package:vorafind/core/visual/visual_repository.dart';

import '../database/test_support.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

Future<void> _insertVideo(
  DriftMediaRepository media, {
  required int id,
  int? dateModified,
  int? durationMs = 60000,
  String? displayName,
}) async {
  await media.upsert(
    buildRecord(
      id: id,
      category: ContentCategory.videos,
      dateModified: dateModified ?? 5000 + id,
      durationMs: durationMs,
      displayName: displayName ?? 'video_$id.mp4',
    ),
    nowSeconds: 1000,
  );
}

Future<void> _insertImage(DriftMediaRepository media, {required int id}) async {
  await media.upsert(buildRecord(id: id), nowSeconds: 1000);
}

/// Frames keyed by the video's content URI; failing keys yield a corrupt
/// error. Deterministic, no real video decoding.
class _FakeSamplerBody implements VideoFrameSampler {
  _FakeSamplerBody({this.framesByKey = const {}, this.failKeys = const {}});

  final Map<String, List<SampledVideoFrame>> framesByKey;
  final Set<String> failKeys;

  @override
  Future<VideoFrameSampling> sampleFrames({
    required String contentUri,
    int maxFrames = VisualDefaults.maxFramesPerVideo,
  }) async {
    if (failKeys.contains(contentUri)) {
      return const VideoFrameSampling(
        frames: [],
        errorCode: VisualSamplerError.corrupt,
      );
    }
    final frames = framesByKey[contentUri] ?? const <SampledVideoFrame>[];
    return VideoFrameSampling(frames: frames.take(maxFrames).toList());
  }
}

SampledVideoFrame _frame(int tsMs, int byte) => SampledVideoFrame(
  frameTsMs: tsMs,
  rgbBytes: Uint8List.fromList(
    List.filled(
      VisualDefaults.inputDimension * VisualDefaults.inputDimension * 3,
      byte,
    ),
  ),
);

String _uri(int id) => 'content://media/external_primary/videos/media/$id';

void main() {
  group('DriftVisualRepository persistence', () {
    late AppDatabase database;
    late DriftMediaRepository media;
    late DriftVisualRepository repository;

    setUp(() {
      database = _db();
      media = DriftMediaRepository(database);
      repository = DriftVisualRepository(database);
    });
    tearDown(() => database.close());

    test(
      'saveAnalysis persists completed status and frame rows with timestamps',
      () async {
        await _insertVideo(media, id: 1);
        await repository.saveAnalysis(
          stableKey: 'external_primary:1',
          sourceRevision: 1,
          modelId: 'm1',
          frames: [
            AnalyzedVisualFrame(
              frameIndex: 0,
              frameTsMs: 3000,
              concepts: const [
                VisualFrameConcept(concept: 'mountain', confidenceLabel: 0.9),
              ],
            ),
            AnalyzedVisualFrame(
              frameIndex: 1,
              frameTsMs: 9000,
              concepts: const [
                VisualFrameConcept(concept: 'mountain', confidenceLabel: 0.5),
              ],
            ),
          ],
          nowEpochSeconds: 2000,
        );

        expect(
          await repository.getStatus('external_primary:1'),
          VisualVideoStatus.completed,
        );
        final rows = await database.select(database.videoVisualFrames).get();
        expect(rows, hasLength(2));
        expect(rows.every((r) => r.stableKey == 'external_primary:1'), isTrue);
        expect(rows.map((r) => r.frameTsMs), containsAll(<int>[3000, 9000]));
        final stats = await repository.stats();
        expect(stats.completed, 1);
        expect(stats.videoFrames, 2);
      },
    );

    test('re-analysis replaces stale frame rows transactionally', () async {
      await _insertVideo(media, id: 1);
      const key = 'external_primary:1';
      await repository.saveAnalysis(
        stableKey: key,
        sourceRevision: 1,
        modelId: 'm1',
        frames: [
          AnalyzedVisualFrame(
            frameIndex: 0,
            frameTsMs: 1000,
            concepts: const [
              VisualFrameConcept(concept: 'beach', confidenceLabel: 0.8),
            ],
          ),
        ],
        nowEpochSeconds: 2000,
      );
      await repository.saveAnalysis(
        stableKey: key,
        sourceRevision: 2,
        modelId: 'm1',
        frames: [
          AnalyzedVisualFrame(
            frameIndex: 0,
            frameTsMs: 5000,
            concepts: const [
              VisualFrameConcept(concept: 'car', confidenceLabel: 0.7),
            ],
          ),
          AnalyzedVisualFrame(
            frameIndex: 1,
            frameTsMs: 15000,
            concepts: const [
              VisualFrameConcept(concept: 'car', confidenceLabel: 0.6),
            ],
          ),
        ],
        nowEpochSeconds: 3000,
      );

      final rows = await database.select(database.videoVisualFrames).get();
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.concept == 'car'), isTrue);
      final status = await (database.select(
        database.videoVisualStatus,
      )..where((s) => s.stableKey.equals(key))).getSingle();
      expect(status.sourceRevision, 2);
    });

    test(
      'saveFailure persists permanent unsupported and transient failed',
      () async {
        await _insertVideo(media, id: 1);
        await _insertVideo(media, id: 2);
        await repository.saveFailure(
          stableKey: 'external_primary:1',
          sourceRevision: 1,
          modelId: 'm1',
          errorCode: 'corrupt',
          nowEpochSeconds: 2000,
          permanent: true,
        );
        await repository.saveFailure(
          stableKey: 'external_primary:2',
          sourceRevision: 1,
          modelId: 'm1',
          errorCode: 'failed',
          nowEpochSeconds: 2000,
          permanent: false,
        );

        expect(
          await repository.getStatus('external_primary:1'),
          VisualVideoStatus.unsupported,
        );
        expect(
          await repository.getStatus('external_primary:2'),
          VisualVideoStatus.failed,
        );
        final stats = await repository.stats();
        expect(stats.unsupported, 1);
        expect(stats.failed, 1);
      },
    );

    test('clear removes both tables', () async {
      await _insertVideo(media, id: 1);
      await repository.saveAnalysis(
        stableKey: 'external_primary:1',
        sourceRevision: 1,
        modelId: 'm1',
        frames: const [],
        nowEpochSeconds: 2000,
      );
      await repository.clear();
      expect(await repository.getStatus('external_primary:1'), isNull);
      expect((await repository.stats()).total, 0);
    });
  });

  group('DriftVisualRepository eligibility', () {
    late AppDatabase database;
    late DriftMediaRepository media;
    late DriftVisualRepository repository;

    setUp(() {
      database = _db();
      media = DriftMediaRepository(database);
      repository = DriftVisualRepository(database);
    });
    tearDown(() => database.close());

    test('missing status rows are candidates, bounded by batchSize', () async {
      for (var i = 1; i <= 3; i++) {
        await _insertVideo(media, id: i);
      }
      final candidates = await repository.findVisualCandidates(
        batchSize: 2,
        modelId: 'm1',
        nowEpochSeconds: 5000,
      );
      expect(candidates, hasLength(2));
      expect(candidates.first.durationMs, isNotNull);
    });

    test('only videos are candidates', () async {
      await _insertVideo(media, id: 1);
      await _insertImage(media, id: 2);
      final candidates = await repository.findVisualCandidates(
        batchSize: 10,
        modelId: 'm1',
        nowEpochSeconds: 5000,
      );
      expect(candidates.map((c) => c.stableKey), ['external_primary:1']);
    });

    test('current completed rows are not re-analyzed', () async {
      await _insertVideo(media, id: 1);
      await repository.saveAnalysis(
        stableKey: 'external_primary:1',
        sourceRevision: 1,
        modelId: 'm1',
        frames: const [],
        nowEpochSeconds: 2000,
      );
      final candidates = await repository.findVisualCandidates(
        batchSize: 10,
        modelId: 'm1',
        nowEpochSeconds: 5000,
      );
      expect(candidates, isEmpty);
    });

    test(
      'stale source revision or stale model id re-queues completed rows',
      () async {
        await _insertVideo(media, id: 1);
        await repository.saveAnalysis(
          stableKey: 'external_primary:1',
          sourceRevision: 1,
          modelId: 'm1',
          frames: const [],
          nowEpochSeconds: 2000,
        );

        // Simulate a media-side metadata change (revision bump) on the video.
        await (database.update(database.mediaItems)
              ..where((m) => m.stableKey.equals('external_primary:1')))
            .write(const MediaItemsCompanion(metadataRevision: Value(3)));
        var candidates = await repository.findVisualCandidates(
          batchSize: 10,
          modelId: 'm1',
          nowEpochSeconds: 5000,
        );
        expect(candidates, hasLength(1));

        // A new model id invalidates the completed row as well.
        await repository.saveAnalysis(
          stableKey: 'external_primary:1',
          sourceRevision: 3,
          modelId: 'm1',
          frames: const [],
          nowEpochSeconds: 3000,
        );
        candidates = await repository.findVisualCandidates(
          batchSize: 10,
          modelId: 'm2',
          nowEpochSeconds: 5000,
        );
        expect(candidates, hasLength(1));
      },
    );

    test('failed rows retry only after the cooldown', () async {
      await _insertVideo(media, id: 1);
      await repository.saveFailure(
        stableKey: 'external_primary:1',
        sourceRevision: 1,
        modelId: 'm1',
        errorCode: 'failed',
        nowEpochSeconds: 2000,
        permanent: false,
      );

      var candidates = await repository.findVisualCandidates(
        batchSize: 10,
        modelId: 'm1',
        nowEpochSeconds: 3000,
        retryCooldownSeconds: 3600,
      );
      expect(candidates, isEmpty);

      candidates = await repository.findVisualCandidates(
        batchSize: 10,
        modelId: 'm1',
        nowEpochSeconds: 2000 + 3600,
        retryCooldownSeconds: 3600,
      );
      expect(candidates, hasLength(1));
    });
  });

  group('DriftVisualRepository retrieval', () {
    late AppDatabase database;
    late DriftMediaRepository media;
    late DriftVisualRepository repository;

    setUp(() {
      database = _db();
      media = DriftMediaRepository(database);
      repository = DriftVisualRepository(database);
    });
    tearDown(() => database.close());

    Future<void> seedVideo(
      int id, {
      required List<(int, int, String, double)> rows,
      int? dateModified,
      int? durationMs = 60000,
    }) async {
      await _insertVideo(
        media,
        id: id,
        dateModified: dateModified,
        durationMs: durationMs,
      );
      await repository.saveAnalysis(
        stableKey: 'external_primary:$id',
        sourceRevision: 1,
        modelId: 'm1',
        frames: [
          for (final (frameIndex, tsMs, concept, confidence) in rows)
            AnalyzedVisualFrame(
              frameIndex: frameIndex,
              frameTsMs: tsMs,
              concepts: [
                VisualFrameConcept(
                  concept: concept,
                  confidenceLabel: confidence,
                ),
              ],
            ),
        ],
        nowEpochSeconds: 2000,
      );
    }

    test('returns best frame per video, highest confidence first', () async {
      await seedVideo(
        1,
        rows: const [
          (0, 1000, 'mountain', 0.5),
          (1, 4000, 'mountain', 0.9),
          (2, 8000, 'mountain', 0.6),
        ],
      );
      await seedVideo(2, rows: const [(0, 2000, 'mountain', 0.7)]);
      await seedVideo(3, rows: const [(0, 3000, 'beach', 0.99)]);

      final matches = await repository.retrieveVisualCandidates(
        concepts: const ['mountain'],
        maxResults: 10,
      );
      expect(matches, hasLength(2));
      expect(matches.first.stableKey, 'external_primary:1');
      expect(matches.first.confidence, 0.9);
      // The timestamp of the *best* frame survives retrieval.
      expect(matches.first.frameTsMs, 4000);
      expect(matches.last.stableKey, 'external_primary:2');
    });

    test('unrelated concepts return nothing (no hallucination)', () async {
      await seedVideo(1, rows: const [(0, 1000, 'mountain', 0.9)]);
      final matches = await repository.retrieveVisualCandidates(
        concepts: const ['dog', 'car'],
        maxResults: 10,
      );
      expect(matches, isEmpty);
    });

    test('below-threshold frames are excluded', () async {
      await seedVideo(1, rows: const [(0, 1000, 'mountain', 0.05)]);
      var matches = await repository.retrieveVisualCandidates(
        concepts: const ['mountain'],
        maxResults: 10,
      );
      expect(matches, isEmpty);

      await seedVideo(2, rows: const [(0, 1000, 'mountain', 0.3)]);
      matches = await repository.retrieveVisualCandidates(
        concepts: const ['mountain'],
        maxResults: 10,
        minConfidence: 0.5,
      );
      // An explicit *higher* threshold still excludes the frame.
      expect(matches, isEmpty);

      await seedVideo(3, rows: const [(0, 1000, 'mountain', 0.6)]);
      matches = await repository.retrieveVisualCandidates(
        concepts: const ['mountain'],
        maxResults: 10,
        minConfidence: 0.5,
      );
      // The explicit threshold is inclusive at the boundary.
      expect(matches.map((m) => m.stableKey), ['external_primary:3']);
    });

    test('empty concept list short-circuits', () async {
      await seedVideo(1, rows: const [(0, 1000, 'mountain', 0.9)]);
      expect(
        await repository.retrieveVisualCandidates(
          concepts: const [],
          maxResults: 10,
        ),
        isEmpty,
      );
    });

    test('date filters apply in SQL', () async {
      await seedVideo(
        1,
        rows: const [(0, 1000, 'mountain', 0.9)],
        dateModified: 1000,
      );
      await seedVideo(
        2,
        rows: const [(0, 1000, 'mountain', 0.8)],
        dateModified: 9000,
      );

      expect(
        (await repository.retrieveVisualCandidates(
          concepts: const ['mountain'],
          maxResults: 10,
          dateFrom: 5000,
        )).map((m) => m.stableKey),
        ['external_primary:2'],
      );
      expect(
        (await repository.retrieveVisualCandidates(
          concepts: const ['mountain'],
          maxResults: 10,
          dateTo: 5000,
        )).map((m) => m.stableKey),
        ['external_primary:1'],
      );
    });

    test('duration filters apply in SQL', () async {
      await seedVideo(
        1,
        rows: const [(0, 1000, 'mountain', 0.9)],
        durationMs: 10000,
      );
      await seedVideo(
        2,
        rows: const [(0, 1000, 'mountain', 0.8)],
        durationMs: 120000,
      );

      expect(
        (await repository.retrieveVisualCandidates(
          concepts: const ['mountain'],
          maxResults: 10,
          minDurationMs: 60000,
        )).map((m) => m.stableKey),
        ['external_primary:2'],
      );
      expect(
        (await repository.retrieveVisualCandidates(
          concepts: const ['mountain'],
          maxResults: 10,
          maxDurationMs: 60000,
        )).map((m) => m.stableKey),
        ['external_primary:1'],
      );
    });

    test('non-video categories can never cross the filter boundary', () async {
      await seedVideo(1, rows: const [(0, 1000, 'mountain', 0.9)]);
      await _insertImage(media, id: 2);
      // Even a corrupt store with a concept row for an image must not leak:
      // the SQL pins category=videos.
      await database
          .into(database.videoVisualFrames)
          .insert(
            VideoVisualFramesCompanion.insert(
              stableKey: 'external_primary:2',
              frameIndex: 0,
              frameTsMs: 0,
              concept: 'mountain',
              confidence: 0.99,
            ),
          );
      final matches = await repository.retrieveVisualCandidates(
        concepts: const ['mountain'],
        maxResults: 10,
        mediaCategories: const ['videos'],
      );
      expect(matches.map((m) => m.stableKey), ['external_primary:1']);
    });

    test('maxResults caps the returned pool', () async {
      await seedVideo(1, rows: const [(0, 1000, 'mountain', 0.9)]);
      await seedVideo(2, rows: const [(0, 1000, 'mountain', 0.8)]);
      await seedVideo(3, rows: const [(0, 1000, 'mountain', 0.7)]);
      final matches = await repository.retrieveVisualCandidates(
        concepts: const ['mountain'],
        maxResults: 2,
      );
      expect(matches, hasLength(2));
    });
  });

  group('VisualIndexCoordinator', () {
    late AppDatabase database;
    late DriftMediaRepository media;
    late DriftVisualRepository repository;
    const key1 = 'external_primary:1';
    const key2 = 'external_primary:2';
    const key3 = 'external_primary:3';

    setUp(() {
      database = _db();
      media = DriftMediaRepository(database);
      repository = DriftVisualRepository(database);
    });
    tearDown(() => database.close());

    Future<void> seedVideos(int count) async {
      for (var i = 1; i <= count; i++) {
        await _insertVideo(media, id: i);
      }
    }

    VisualIndexCoordinator coordinator({
      required VideoFrameSampler sampler,
      VisualFrameClassifier? classifier,
    }) => VisualIndexCoordinator(
      classifier: classifier ?? const DeterministicVisualFrameClassifier(),
      sampler: sampler,
      repository: repository,
      batchSize: 2,
    );

    Future<List<VisualRunProgress>> drain(VisualIndexCoordinator c) async {
      final events = <VisualRunProgress>[];
      await for (final event in c.run()) {
        events.add(event);
      }
      return events;
    }

    test(
      'unavailable classifier short-circuits without touching the store',
      () async {
        await seedVideos(1);
        final events = await drain(
          coordinator(
            sampler: _FakeSamplerBody(),
            classifier: _UnavailableClassifier(),
          ),
        );
        expect(events.single.status, VisualRunStatus.unavailable);
        expect(await repository.getStatus(key1), isNull);
      },
    );

    test('successful run persists frames and completes', () async {
      await seedVideos(2);
      final sampler = _FakeSamplerBody(
        framesByKey: {
          _uri(1): [_frame(0, 0x10), _frame(30000, 0x30)],
          _uri(2): [_frame(0, 0x20)],
        },
      );
      final events = await drain(coordinator(sampler: sampler));

      expect(events.last.status, VisualRunStatus.completed);
      expect(events.last.processed, 2);
      expect(events.last.succeeded, 2);
      expect(events.last.failed, 0);
      expect(await repository.getStatus(key1), VisualVideoStatus.completed);
      expect(await repository.getStatus(key2), VisualVideoStatus.completed);
      final frames1 = await (database.select(
        database.videoVisualFrames,
      )..where((f) => f.stableKey.equals(key1))).get();
      expect(
        frames1.map((f) => f.concept),
        containsAll(<String>['mountain', 'car']),
      );
    });

    test(
      'per-video failure isolation: one bad video does not stop the run',
      () async {
        await seedVideos(3);
        final sampler = _FakeSamplerBody(
          failKeys: {_uri(2)},
          framesByKey: {
            _uri(1): [_frame(0, 0x10)],
            _uri(3): [_frame(0, 0x40)],
          },
        );
        final events = await drain(coordinator(sampler: sampler));

        expect(events.last.status, VisualRunStatus.completed);
        expect(events.last.succeeded, 2);
        expect(events.last.failed, 1);
        expect(await repository.getStatus(key1), VisualVideoStatus.completed);
        expect(await repository.getStatus(key2), VisualVideoStatus.unsupported);
        expect(await repository.getStatus(key3), VisualVideoStatus.completed);
      },
    );

    test(
      'a video with zero decodable frames is terminal unsupported',
      () async {
        await seedVideos(1);
        final events = await drain(coordinator(sampler: _FakeSamplerBody()));
        expect(events.last.succeeded, 0);
        expect(await repository.getStatus(key1), VisualVideoStatus.unsupported);
      },
    );

    test('cancellation stops between batches and keeps prior work', () async {
      await seedVideos(3);
      final sampler = _FakeSamplerBody(
        framesByKey: {
          _uri(1): [_frame(0, 0x10)],
          _uri(2): [_frame(0, 0x20)],
          _uri(3): [_frame(0, 0x30)],
        },
      );
      final visualCoordinator = coordinator(sampler: sampler);
      final events = <VisualRunProgress>[];
      await for (final event in visualCoordinator.run()) {
        events.add(event);
        // Cancel after the first batch (batchSize = 2) completes.
        if (event.processed >= 2) visualCoordinator.cancel();
      }
      expect(events.last.status, VisualRunStatus.cancelled);
      // Already-analyzed work stays valid.
      expect(await repository.getStatus(key1), VisualVideoStatus.completed);
      expect(await repository.getStatus(key2), VisualVideoStatus.completed);
      expect(await repository.getStatus(key3), isNull);
    });

    test(
      'resumability: a cancelled run picks up the remaining queue',
      () async {
        await seedVideos(3);
        final sampler = _FakeSamplerBody(
          framesByKey: {
            for (var i = 1; i <= 3; i++) _uri(i): [_frame(0, 0x10)],
          },
        );
        final first = coordinator(sampler: sampler);
        await for (final event in first.run()) {
          if (event.processed >= 2) first.cancel();
        }
        final second = coordinator(sampler: sampler);
        final events = await drain(second);
        expect(events.last.status, VisualRunStatus.completed);
        expect(await repository.getStatus(key3), VisualVideoStatus.completed);
      },
    );
  });

  group('VideoFrameSampler', () {
    test('unavailable sampler reports platformUnavailable', () async {
      final result = await const UnavailableVideoFrameSampler().sampleFrames(
        contentUri: 'content://x',
      );
      expect(result.errorCode, VisualSamplerError.platformUnavailable);
      expect(result.frames, isEmpty);
    });

    test(
      'method channel parses frames and survives a missing plugin',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final channel = const MethodChannel('vorafind/test/video');
        final sampler = MethodChannelVideoFrameSampler(channel: channel);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

        messenger.setMockMethodCallHandler(channel, (call) async {
          return {
            'durationMs': 60000,
            'frames': [
              {'tsMs': 0, 'rgb': Uint8List.fromList(List.filled(9, 7))},
              {'tsMs': 30000, 'rgb': Uint8List.fromList(List.filled(9, 8))},
            ],
          };
        });
        final ok = await sampler.sampleFrames(contentUri: 'content://x');
        expect(ok.errorCode, isNull);
        expect(ok.durationMs, 60000);
        expect(ok.frames, hasLength(2));
        expect(ok.frames[1].frameTsMs, 30000);
        messenger.setMockMethodCallHandler(channel, null);

        // No handler → MissingPluginException path.
        final missing = await sampler.sampleFrames(contentUri: 'content://x');
        expect(missing.errorCode, VisualSamplerError.platformUnavailable);
      },
    );
  });

  group('VisualFrameClassifier', () {
    test('deterministic classifier is stable and sorted', () async {
      const classifier = DeterministicVisualFrameClassifier();
      final bytes = Uint8List.fromList(List.filled(9, 0x80));
      final a = await classifier.classify(rgbBytes: bytes);
      final b = await classifier.classify(rgbBytes: bytes);
      expect(
        a.concepts.map((c) => c.concept),
        b.concepts.map((c) => c.concept),
      );
      expect(
        a.concepts.map((c) => c.confidenceLabel),
        b.concepts.map((c) => c.confidenceLabel),
      );
      final confidences = a.concepts.map((c) => c.confidenceLabel).toList();
      expect(
        confidences,
        equals([...confidences]..sort((x, y) => y.compareTo(x))),
      );
    });

    test('unknown frames yield no concepts', () async {
      const classifier = DeterministicVisualFrameClassifier();
      final result = await classifier.classify(
        rgbBytes: Uint8List.fromList(List.filled(9, 0xEE)),
      );
      expect(result.concepts, isEmpty);
    });

    test(
      'neural classifier constructs cheaply and stays available before load',
      () {
        final classifier = NeuralVisualFrameClassifier();
        expect(classifier.isAvailable, isTrue);
        expect(classifier.modelId, VisualDefaults.visualModelId);
      },
    );

    test('concept map is deterministic and word-boundary safe', () {
      expect(
        VisualConceptMap.conceptsForLabel('sports car, sport car'),
        contains('car'),
      );
      expect(
        VisualConceptMap.conceptsForLabel('tabby, tabby cat'),
        contains('cat'),
      );
      expect(
        VisualConceptMap.conceptsForLabel('carbon'),
        isNot(contains('car')),
      );
      expect(
        VisualConceptMap.conceptsForTokens(['mountains']),
        contains('mountain'),
      );
      expect(
        VisualConceptMap.conceptsForTokens(['beaches']),
        contains('beach'),
      );
      expect(VisualConceptMap.conceptsForTokens(['zebra']), isEmpty);
      for (final definition in VisualConceptMap.definitions) {
        expect(VisualConceptMap.contains(definition.concept), isTrue);
      }
    });
  });

  group('SearchService visual integration', () {
    late AppDatabase database;
    late DriftMediaRepository media;
    late DriftVisualRepository visual;
    late SearchService service;

    setUp(() {
      database = _db();
      media = DriftMediaRepository(database);
      visual = DriftVisualRepository(database);
      service = SearchService(
        repository: media,
        visualSearchRepository: visual,
      );
    });
    tearDown(() => database.close());

    Future<void> seedMountainVideo(int id, double confidence, int tsMs) async {
      await _insertVideo(
        media,
        id: id,
        dateModified: 5000 + id,
        durationMs: 60000,
      );
      await visual.saveAnalysis(
        stableKey: 'external_primary:$id',
        sourceRevision: 1,
        modelId: 'm1',
        frames: [
          AnalyzedVisualFrame(
            frameIndex: 0,
            frameTsMs: tsMs,
            concepts: [
              VisualFrameConcept(
                concept: 'mountain',
                confidenceLabel: confidence,
              ),
            ],
          ),
        ],
        nowEpochSeconds: 2000,
      );
    }

    test('a mountain query retrieves visual video matches', () async {
      await seedMountainVideo(1, 0.9, 42000);
      await seedMountainVideo(2, 0.6, 12000);

      final results = await service.search(
        const SearchQuery(
          text: 'mountain video',
          categories: [ContentCategory.videos],
        ),
      );
      final keys = results.map((r) => r.stableKey).toSet();
      expect(
        keys,
        containsAll(<String>['external_primary:1', 'external_primary:2']),
      );
      final best = results.firstWhere(
        (r) => r.stableKey == 'external_primary:1',
      );
      expect(best.visualConcept, 'mountain');
      // Higher-confidence match outranks the weaker one.
      final other = results.firstWhere(
        (r) => r.stableKey == 'external_primary:2',
      );
      expect(best.score, greaterThan(other.score));
      // Timestamp preserved all the way through to the result.
      expect(best.visualFrameTsMs, 42000);
    });

    test('multiple matching frames collapse to one video result', () async {
      await _insertVideo(media, id: 1, durationMs: 60000);
      await visual.saveAnalysis(
        stableKey: 'external_primary:1',
        sourceRevision: 1,
        modelId: 'm1',
        frames: [
          AnalyzedVisualFrame(
            frameIndex: 0,
            frameTsMs: 10000,
            concepts: const [
              VisualFrameConcept(concept: 'mountain', confidenceLabel: 0.5),
            ],
          ),
          AnalyzedVisualFrame(
            frameIndex: 1,
            frameTsMs: 30000,
            concepts: const [
              VisualFrameConcept(concept: 'mountain', confidenceLabel: 0.95),
            ],
          ),
          AnalyzedVisualFrame(
            frameIndex: 2,
            frameTsMs: 50000,
            concepts: const [
              VisualFrameConcept(concept: 'mountain', confidenceLabel: 0.7),
            ],
          ),
        ],
        nowEpochSeconds: 2000,
      );

      final results = await service.search(
        const SearchQuery(
          text: 'mountain video',
          categories: [ContentCategory.videos],
        ),
      );
      final matches = results
          .where((r) => r.stableKey == 'external_primary:1')
          .toList();
      expect(matches, hasLength(1));
      expect(matches.single.visualConcept, 'mountain');
      expect(matches.single.visualFrameTsMs, 30000);
    });

    test('unrelated visual queries return no visual-only results', () async {
      await seedMountainVideo(1, 0.9, 42000);
      final results = await service.search(
        const SearchQuery(
          text: 'dog video',
          categories: [ContentCategory.videos],
        ),
      );
      expect(results.where((r) => r.visualConcept != null), isEmpty);
    });

    test('exact filename match outranks a visual-only match', () async {
      // Video 1: filename says "mountain" (exact keyword hit), weak visuals.
      await _insertVideo(media, id: 1, displayName: 'mountain.mp4');
      await visual.saveAnalysis(
        stableKey: 'external_primary:1',
        sourceRevision: 1,
        modelId: 'm1',
        frames: [
          AnalyzedVisualFrame(
            frameIndex: 0,
            frameTsMs: 1000,
            concepts: const [
              VisualFrameConcept(concept: 'mountain', confidenceLabel: 0.3),
            ],
          ),
        ],
        nowEpochSeconds: 2000,
      );
      // Video 2: generic filename, strong visual match only.
      await seedMountainVideo(2, 0.9, 42000);

      final results = await service.search(
        const SearchQuery(
          text: 'mountain video',
          categories: [ContentCategory.videos],
        ),
      );
      expect(results.first.stableKey, 'external_primary:1');
    });

    test('visual retrieval failure never breaks search', () async {
      await _insertVideo(media, id: 1, durationMs: 60000);
      final brokenService = SearchService(
        repository: media,
        visualSearchRepository: _ThrowingVisualRepository(),
      );
      final results = await brokenService.search(
        const SearchQuery(
          text: 'mountain video',
          categories: [ContentCategory.videos],
        ),
      );
      expect(results, isA<List<SearchResult>>());
    });
  });
}

class _UnavailableClassifier implements VisualFrameClassifier {
  @override
  String get modelId => 'unavailable';
  @override
  bool get isAvailable => false;
  @override
  Future<VisualFrameClassification> classify({
    required Uint8List rgbBytes,
  }) async {
    throw const VisualClassificationException(VisualErrorCode.unavailable);
  }

  @override
  Future<void> dispose() async {}
}

class _ThrowingVisualRepository implements VisualSearchRepository {
  @override
  Future<List<VisualRetrievalMatch>> retrieveVisualCandidates({
    required List<String> concepts,
    required int maxResults,
    List<String>? mediaCategories,
    int? dateFrom,
    int? dateTo,
    int? minDurationMs,
    int? maxDurationMs,
    double minConfidence = VisualDefaults.minConceptConfidence,
  }) async {
    throw StateError('visual store unavailable');
  }
}
