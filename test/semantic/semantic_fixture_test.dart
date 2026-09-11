import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/core/semantic/embedding_provider.dart';
import 'package:vorafind/core/semantic/semantic_models.dart';
import 'package:vorafind/core/semantic/vector_math.dart';

void main() {
  group('semantic retrieval fixtures', () {
    late DeterministicEmbeddingProvider provider;

    setUp(() {
      provider = const DeterministicEmbeddingProvider();
    });

    test(
      'documents about computers learning data are semantically closer',
      () async {
        // A document about machine learning.
        final mlDoc = await provider.embed(
          SemanticInputBuilder.forDocument(
            displayName: 'Machine Learning Fundamentals.pdf',
            extractedText:
                'A guide to computers learning from data. Training models, '
                'classification, regression and neural networks.',
          ),
        );

        // A query about computers learning from data — shares vocabulary.
        final query = await provider.embed('computers learning from data');

        // An unrelated document.
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
        // The ML document shares vocabulary tokens with the query, so its
        // cosine similarity must be higher than the recipe's.
        expect(mlSim! > recipeSim!, isTrue);
      },
    );

    test('images with shared OCR context score higher', () async {
      final mountain = await provider.embed(
        SemanticInputBuilder.forMedia(
          displayName: 'Trip.jpg',
          ocrText:
              'A beautiful mountain landscape with snow, '
              'hiking trails and rocky peaks.',
          isScreenshot: false,
        ),
      );

      final query = await provider.embed('mountain trip photo');

      final beach = await provider.embed(
        SemanticInputBuilder.forMedia(
          displayName: 'Beach.jpg',
          ocrText: 'A sunny beach with palm trees and ocean waves.',
          isScreenshot: false,
        ),
      );

      final mountainSim = VectorMath.cosine(query, mountain);
      final beachSim = VectorMath.cosine(query, beach);

      expect(mountainSim, isNotNull);
      expect(beachSim, isNotNull);
      expect(mountainSim! > beachSim!, isTrue);
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

      // Same core text but the screenshot version has the extra
      // 'screenshot context' token, so the vectors must differ.
      expect(screenshot, isNot(equals(photo)));
    });

    test('empty input yields zero vector (unsupported)', () async {
      final empty = await provider.embed('');
      expect(empty.length, 384);
      expect(empty.every((v) => v == 0.0), isTrue);
    });

    test('bounded input is truncated without error', () async {
      final huge = 'word ' * 10000;
      final vector = await provider.embed(huge);
      expect(vector.length, 384);
      var norm = 0.0;
      for (final v in vector) {
        norm += v * v;
      }
      expect(norm > 0, isTrue);
    });
  });
}
