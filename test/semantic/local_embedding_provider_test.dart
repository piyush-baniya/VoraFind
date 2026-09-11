import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/core/semantic/local_embedding_provider.dart';
import 'package:vorafind/core/semantic/semantic_models.dart';
import 'package:vorafind/core/semantic/vector_math.dart';

void main() {
  late LocalEmbeddingProvider provider;

  setUp(() {
    provider = const LocalEmbeddingProvider();
  });

  group('LocalEmbeddingProvider', () {
    test('reports correct model identity', () {
      expect(provider.modelId, 'local-ngram-rp-384');
      expect(provider.dimensions, 384);
      expect(provider.isAvailable, isTrue);
    });

    test('embed produces a vector of correct dimensions', () async {
      final vector = await provider.embed('hello world');
      expect(vector.length, 384);
    });

    test('embed is deterministic — same input produces same vector', () async {
      final a = await provider.embed('machine learning');
      final b = await provider.embed('machine learning');
      expect(a, equals(b));
    });

    test('L2-normalized vector has unit norm', () async {
      final vector = await provider.embed('test input text');
      var norm = 0.0;
      for (final v in vector) {
        norm += v * v;
      }
      expect(norm, closeTo(1.0, 1e-6));
    });

    test('empty input yields zero vector (unsupported)', () async {
      final vector = await provider.embed('');
      expect(vector.length, 384);
      expect(vector.every((v) => v == 0.0), isTrue);
    });

    test('whitespace-only input yields zero vector', () async {
      final vector = await provider.embed('   ');
      expect(vector.length, 384);
      expect(vector.every((v) => v == 0.0), isTrue);
    });

    test(
      'input longer than maxInputChars is truncated without error',
      () async {
        final huge = 'word ' * 10000;
        final vector = await provider.embed(huge);
        expect(vector.length, 384);
        var norm = 0.0;
        for (final v in vector) {
          norm += v * v;
        }
        expect(norm > 0, isTrue);
      },
    );

    test('similar texts score higher than unrelated texts', () async {
      final query = await provider.embed('mountain hiking adventure trip');
      final mountain = await provider.embed(
        SemanticInputBuilder.forMedia(
          displayName: 'Mountain.jpg',
          ocrText: 'A hiking trip through mountain trails with stunning views',
          isScreenshot: false,
        ),
      );
      final recipe = await provider.embed(
        SemanticInputBuilder.forMedia(
          displayName: 'Pancake Recipe.txt',
          ocrText: 'Flour, eggs, milk, butter, sugar for making pancakes',
          isScreenshot: false,
        ),
      );

      final mtSim = VectorMath.cosine(query, mountain);
      final rcSim = VectorMath.cosine(query, recipe);

      expect(mtSim, isNotNull);
      expect(rcSim, isNotNull);
      expect(mtSim! > rcSim!, isTrue);
    });

    test('documents with shared vocabulary score higher', () async {
      final query = await provider.embed('computers learning from data');
      final mlDoc = await provider.embed(
        SemanticInputBuilder.forDocument(
          displayName: 'Machine Learning Fundamentals.pdf',
          extractedText:
              'A guide to computers learning from data. Training models, '
              'classification, regression and neural networks.',
        ),
      );
      final recipe = await provider.embed(
        SemanticInputBuilder.forDocument(
          displayName: 'Pancake Recipe.txt',
          extractedText:
              'How to make pancakes. Flour, eggs, milk, butter, sugar.',
        ),
      );

      final mlSim = VectorMath.cosine(query, mlDoc);
      final recipeSim = VectorMath.cosine(query, recipe);

      expect(mlSim, isNotNull);
      expect(recipeSim, isNotNull);
      expect(mlSim! > recipeSim!, isTrue);
    });

    test(
      'embedBatch returns correct count and each has correct dimensions',
      () async {
        final vectors = await provider.embedBatch(['hello', 'world', 'test']);
        expect(vectors.length, 3);
        for (final v in vectors) {
          expect(v.length, 384);
        }
      },
    );

    test('embedBatch is deterministic per element', () async {
      final a = await provider.embedBatch(['hello', 'world']);
      final b = await provider.embedBatch(['hello', 'world']);
      expect(a[0], equals(b[0]));
      expect(a[1], equals(b[1]));
    });

    test('screenshots with screenshot context are distinguishable', () async {
      final screenshot = await provider.embed(
        SemanticInputBuilder.forMedia(
          displayName: 'Error.png',
          ocrText: 'Flutter exception stack trace error',
          isScreenshot: true,
        ),
      );
      final photo = await provider.embed(
        SemanticInputBuilder.forMedia(
          displayName: 'Error.png',
          ocrText: 'Flutter exception stack trace error',
          isScreenshot: false,
        ),
      );
      expect(screenshot, isNot(equals(photo)));
    });

    test('vector contains no NaN or Infinity', () async {
      final vector = await provider.embed(
        'test with unicode: café résumé ñ 中文',
      );
      expect(vector.any((v) => v.isNaN), isFalse);
      expect(vector.any((v) => v.isInfinite), isFalse);
    });

    test(
      'similar phrasings with shared n-grams score higher than unrelated text',
      () async {
        final a = await provider.embed('machine learning from data');
        final b = await provider.embed('learning from data with machine');
        final unrelated = await provider.embed('recipe cooking flour eggs');

        final abSim = VectorMath.cosine(a, b);
        final aUnrelSim = VectorMath.cosine(a, unrelated);

        expect(abSim, isNotNull);
        expect(aUnrelSim, isNotNull);
        // Same words in different order share more n-grams than unrelated text.
        expect(abSim! > aUnrelSim!, isTrue);
      },
    );

    test('different inputs produce different vectors', () async {
      final a = await provider.embed('hello world');
      final b = await provider.embed('completely different content here');
      expect(a, isNot(equals(b)));
    });
  });
}
