import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/semantic/semantic_models.dart';
import 'package:vorafind/core/semantic/drift_semantic_repository.dart';

void main() {
  late AppDatabase db;
  late DriftSemanticRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftSemanticRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('indexing', () {
    test('saveEmbedding stores completed embedding', () async {
      final now = DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      await repo.saveEmbedding(
        stableKey: 'media:1',
        contentType: SemanticContentType.media,
        sourceRevision: 1,
        modelId: 'm1',
        vector: [0.1, 0.2, 0.3, 0.4],
        nowEpochSeconds: now,
      );
      final status = await repo.getStatus('media:1', SemanticContentType.media);
      expect(status, SemanticEmbeddingStatus.completed);
    });

    test('saveEmbedding updates stale revision', () async {
      final now = DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      await repo.saveEmbedding(
        stableKey: 'media:1',
        contentType: SemanticContentType.media,
        sourceRevision: 1,
        modelId: 'm1',
        vector: [0.1, 0.2, 0.3, 0.4],
        nowEpochSeconds: now,
      );
      await repo.saveEmbedding(
        stableKey: 'media:1',
        contentType: SemanticContentType.media,
        sourceRevision: 2,
        modelId: 'm1',
        vector: [0.5, 0.6, 0.7, 0.8],
        nowEpochSeconds: now + 1,
      );
      final status = await repo.getStatus('media:1', SemanticContentType.media);
      expect(status, SemanticEmbeddingStatus.completed);
    });

    test('saveFailure records error status', () async {
      final now = DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      await repo.saveFailure(
        stableKey: 'media:1',
        contentType: SemanticContentType.media,
        sourceRevision: 1,
        modelId: 'm1',
        errorCode: 'provider_error',
        nowEpochSeconds: now,
        permanent: false,
      );
      final status = await repo.getStatus('media:1', SemanticContentType.media);
      expect(status, SemanticEmbeddingStatus.failed);
    });

    test('clear removes all embeddings', () async {
      final now = DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      await repo.saveEmbedding(
        stableKey: 'media:1',
        contentType: SemanticContentType.media,
        sourceRevision: 1,
        modelId: 'm1',
        vector: [0.1, 0.2, 0.3, 0.4],
        nowEpochSeconds: now,
      );
      await repo.clear();
      final status = await repo.getStatus('media:1', SemanticContentType.media);
      expect(status, isNull);
    });
  });
}
