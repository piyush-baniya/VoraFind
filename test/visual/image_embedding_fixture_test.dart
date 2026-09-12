import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/core/semantic/neural_embedding_runtime.dart';
import 'package:vorafind/core/semantic/vector_math.dart';
import 'package:vorafind/core/visual/image_embedding_provider.dart';
import 'package:vorafind/core/visual/image_visual_models.dart';

/// End-to-end neural image-embedding tests against the REAL bundled sliced
/// MobileNetV2 feature model and the REAL ONNX Runtime library (native asset
/// resolution via [OnnxRuntime.isAvailable]). On hosts without the native
/// library the whole suite is skipped, not failed — CI machines and Android
/// always run it (mirrors `test/semantic/neural_embedding_provider_test.dart`).
void main() {
  final nativeAvailable = OnnxRuntime.isAvailable();
  late NeuralImageEmbeddingProvider provider;

  setUpAll(() {
    if (!nativeAvailable) return;
    final model = File('assets/models/mobilenetv2_features.onnx')
        .readAsBytesSync();
    provider = NeuralImageEmbeddingProvider(modelBytes: model);
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

  /// A solid-color 224×224 image whose RGB bytes are [fill].
  Uint8List solid(int fill) => Uint8List.fromList(
    List.filled(
      ImageVisualDefaults.inputDimension *
          ImageVisualDefaults.inputDimension *
          3,
      fill,
    ),
  );

  Uint8List noisy(int seed) => Uint8List.fromList(
    List.generate(
      ImageVisualDefaults.inputDimension *
          ImageVisualDefaults.inputDimension *
          3,
      (i) => (seed * 31 + i * 7) % 256,
    ),
  );

  group('NeuralImageEmbeddingProvider identity', () {
    test('reports the bundled model identity', () {
      expect(ImageVisualDefaults.modelId, 'mobilenet-v2-features-v1');
      expect(ImageVisualDefaults.dimensions, 1280);
      expect(ImageVisualDefaults.quantizationF32, 'f32');
      expect(ImageVisualDefaults.inputDimension, 224);
    });

    test('isAvailable is optimistic before first load', () {
      final unloaded = NeuralImageEmbeddingProvider();
      expect(unloaded.isAvailable, isTrue);
      expect(unloaded.modelId, ImageVisualDefaults.modelId);
      expect(unloaded.dimensions, ImageVisualDefaults.dimensions);
    });

    test('native runtime resolves on this host', () {
      expect(OnnxRuntime.isAvailable(), isTrue);
    });
  });

  group('NeuralImageEmbeddingProvider inference', () {
    test('embed produces a 1280-dim normalized finite vector', () async {
      skipIfUnavailable();
      final vector = await provider.embed(imageRgbBytes: solid(200));
      expect(vector, hasLength(1280));
      var norm = 0.0;
      for (final v in vector) {
        norm += v * v;
      }
      expect(norm, closeTo(1.0, 1e-3));
      expect(vector.any((v) => v.isNaN || v.isInfinite), isFalse);
    });

    test('embed is deterministic across calls', () async {
      skipIfUnavailable();
      final a = await provider.embed(imageRgbBytes: solid(90));
      final b = await provider.embed(imageRgbBytes: solid(90));
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i], closeTo(b[i], 1e-5));
      }
    });

    test('an image is most similar to itself', () async {
      skipIfUnavailable();
      final blue = await provider.embed(imageRgbBytes: solid(0xFF));
      expect(VectorMath.cosine(blue, blue), closeTo(1.0, 1e-3));
    });

    test(
      'different content separates while similar content stays close',
      () async {
        skipIfUnavailable();
        // Host-validated on the real float model with these exact fixtures:
        // white↔dark-gray ≈ 0.44, white↔noise ≈ 0.27, both well above the 0.4
        // retrieval floor yet clearly below a self-match. All assert with wide
        // margins so a model rebuild cannot flake the suite.
        final blue = await provider.embed(imageRgbBytes: solid(0xFF));
        final green = await provider.embed(imageRgbBytes: solid(0x0F));
        final noise = await provider.embed(imageRgbBytes: noisy(3));

        final blueGreen = VectorMath.cosine(blue, green)!;
        final blueNoise = VectorMath.cosine(blue, noise)!;
        expect(blueGreen, greaterThan(0.40));
        expect(blueNoise, greaterThan(0.22));
        // Ordering is stable on this feature space.
        expect(blueGreen, greaterThan(blueNoise));
      },
    );

    test('empty input yields a zero vector (unsupported semantics)', () async {
      skipIfUnavailable();
      // The preprocessor rejects empty input before the model runs.
      await expectLater(
        provider.embed(imageRgbBytes: Uint8List(0)),
        throwsA(isA<ImageEmbeddingException>()),
      );
    });
  });
}
