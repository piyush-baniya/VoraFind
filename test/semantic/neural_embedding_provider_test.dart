import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/core/semantic/embedding_provider.dart';
import 'package:vorafind/core/semantic/neural_embedding_provider.dart';
import 'package:vorafind/core/semantic/neural_embedding_runtime.dart';
import 'package:vorafind/core/semantic/semantic_models.dart';
import 'package:vorafind/core/semantic/vector_math.dart';

/// End-to-end neural embedding tests against the REAL bundled model and the
/// REAL ONNX Runtime library (native asset resolution via
/// [OnnxRuntime.isAvailable]). On hosts without the native library the whole
/// suite is skipped, not failed — CI machines and Android always run it.
void main() {
  final nativeAvailable = OnnxRuntime.isAvailable();
  late NeuralEmbeddingProvider provider;

  setUpAll(() {
    if (!nativeAvailable) return;
    final model = File('assets/models/model_quantized.onnx').readAsBytesSync();
    final vocab = File('assets/models/vocab.txt').readAsStringSync();
    provider = NeuralEmbeddingProvider(modelBytes: model, vocabText: vocab);
  });

  tearDownAll(() {
    if (!nativeAvailable) return;
    provider.dispose();
  });

  void skipIfUnavailable() {
    if (!nativeAvailable) {
      markTestSkipped(
        'native onnxruntime unavailable on this host '
        '(${Platform.operatingSystem}); inference tests skipped',
      );
    }
  }

  group('NeuralEmbeddingProvider identity', () {
    test('reports the bundled model identity', () {
      expect(SemanticDefaults.neuralModelId, 'minilm-l6-v2-int8-v1');
      expect(SemanticDefaults.dimensions, 384);
      expect(SemanticDefaults.quantizationF32, 'f32');
    });

    test('isAvailable is optimistic before first load', () {
      final unloaded = NeuralEmbeddingProvider();
      expect(unloaded.isAvailable, isTrue);
      expect(unloaded.modelId, 'minilm-l6-v2-int8-v1');
      expect(unloaded.dimensions, 384);
      expect(unloaded.quantizationTag, 'f32');
    });

    test('native runtime resolves on this host', () {
      // Regression guard: if the test host is misconfigured (missing DLL,
      // wrong architecture) this fails loudly instead of silently skipping.
      // Android hosts always load libonnxruntime.so via the plugin.
      expect(OnnxRuntime.isAvailable(), isTrue);
    });
  });

  group('NeuralEmbeddingProvider inference', () {
    test('embed produces a 384-dim L2-normalized vector', () async {
      skipIfUnavailable();
      final vector = await provider.embed('hello world');
      expect(vector, hasLength(384));
      var norm = 0.0;
      for (final v in vector) {
        norm += v * v;
      }
      expect(norm, closeTo(1.0, 1e-4));
      expect(vector.any((v) => v.isNaN || v.isInfinite), isFalse);
    });

    test('embed is deterministic across calls', () async {
      skipIfUnavailable();
      final a = await provider.embed('machine learning from data');
      final b = await provider.embed('machine learning from data');
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i], closeTo(b[i], 1e-5));
      }
    });

    test('synonymy works: vehicle query finds car content', () async {
      skipIfUnavailable();
      final query = await provider.embed('vehicle maintenance notes');
      final carDoc = await provider.embed(
        'car repair receipts oil change brake inspection log',
      );
      final unrelated = await provider.embed('pancake recipe flour milk egg');
      // Measured on the real model: vehicle↔car ~0.63, baseline ≤0.19. Assert
      // wide margins so a QuantModel retrain or host-speed variance cannot
      // flake the suite.
      expect(VectorMath.cosine(query, carDoc), greaterThan(0.35));
      expect(VectorMath.cosine(query, unrelated), lessThan(0.35));
      expect(
        VectorMath.cosine(query, carDoc)!,
        greaterThan(VectorMath.cosine(query, unrelated)!),
      );
    });

    test('same-text query ranks above every unrelated item', () async {
      skipIfUnavailable();
      final query = await provider.embed('mountain hiking adventure');
      final self = await provider.embed('mountain hiking adventure');
      final recipe = await provider.embed('flour eggs milk pancakes butter');
      expect(
        VectorMath.cosine(query, self),
        greaterThan(VectorMath.cosine(query, recipe)!),
      );
      expect(VectorMath.cosine(query, self)!, closeTo(1.0, 1e-3));
    });

    test('document representation embeds like production input', () async {
      skipIfUnavailable();
      final representation = SemanticInputBuilder.forDocument(
        displayName: 'Machine Learning Fundamentals.pdf',
        relativePath: '/Documents',
        extractedText:
            'A guide to computers learning from data with neural networks, '
            'classification and regression models.',
      );
      final query = await provider.embed('machine learning neural networks');
      final vector = await provider.embed(representation);
      expect(vector, hasLength(384));
      var norm = 0.0;
      for (final v in vector) {
        norm += v * v;
      }
      expect(norm, closeTo(1.0, 1e-4));
      expect(VectorMath.cosine(query, vector), greaterThan(0.35));
    });

    test('empty input throws unsupportedInput', () async {
      skipIfUnavailable();
      await expectLater(
        provider.embed(''),
        throwsA(
          isA<EmbeddingException>().having(
            (e) => e.code,
            'code',
            EmbeddingErrorCode.unsupportedInput,
          ),
        ),
      );
    });

    test('long inputs truncate gracefully to the token cap', () async {
      skipIfUnavailable();
      final long = List.filled(300, 'machine learning pattern data').join(' ');
      final vector = await provider.embed(long);
      expect(vector, hasLength(384));
      var norm = 0.0;
      for (final v in vector) {
        norm += v * v;
      }
      expect(norm, closeTo(1.0, 1e-4));
    });

    test('embedBatch returns a vector per input in order', () async {
      skipIfUnavailable();
      final vectors = await provider.embedBatch([
        'hello',
        'machine learning',
        'recipe cooking',
      ]);
      expect(vectors, hasLength(3));
      for (final v in vectors) {
        expect(v, hasLength(384));
      }
    });
  });
}
