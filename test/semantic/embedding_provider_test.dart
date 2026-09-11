import 'package:flutter_test/flutter_test.dart';
import 'package:vorafind/core/semantic/embedding_provider.dart';

void main() {
  group('DeterministicEmbeddingProvider', () {
    late DeterministicEmbeddingProvider provider;

    setUp(() {
      provider = const DeterministicEmbeddingProvider(dimensions: 8);
    });

    test('reports model identity', () {
      expect(provider.modelId, 'deterministic-8');
      expect(provider.dimensions, 8);
      expect(provider.isAvailable, isTrue);
    });

    test('generates deterministic embeddings for same text', () async {
      final a = await provider.embed('hello world');
      final b = await provider.embed('hello world');
      expect(a, b);
    });

    test('generates different embeddings for different text', () async {
      final a = await provider.embed('hello');
      final b = await provider.embed('goodbye');
      expect(a, isNot(equals(b)));
    });

    test('returns correct dimensions', () async {
      final embedding = await provider.embed('test');
      expect(embedding.length, 8);
    });

    test('batch generation returns correct count', () async {
      final embeddings = await provider.embedBatch(['a', 'b', 'c']);
      expect(embeddings.length, 3);
      for (final e in embeddings) {
        expect(e.length, 8);
      }
    });

    test('empty text produces a zero vector', () async {
      final embedding = await provider.embed('');
      expect(embedding.length, 8);
      expect(embedding.every((v) => v == 0.0), isTrue);
    });

    test('dispose cleans up cleanly', () {
      expect(() => provider.dispose(), returnsNormally);
    });
  });

  group('DeterministicEmbeddingProvider.staleness', () {
    test('embedding changes when dimensions change', () {
      const p1 = DeterministicEmbeddingProvider(dimensions: 4);
      const p2 = DeterministicEmbeddingProvider(dimensions: 8);
      expect(p1.dimensions, isNot(equals(p2.dimensions)));
    });
  });

  group('UnavailableEmbeddingProvider', () {
    test('reports unavailable', () {
      const provider = UnavailableEmbeddingProvider();
      expect(provider.isAvailable, isFalse);
      expect(provider.modelId, 'unavailable');
    });

    test('embed throws unavailable', () {
      const provider = UnavailableEmbeddingProvider();
      expect(() => provider.embed('test'), throwsA(isA<EmbeddingException>()));
    });
  });
}
