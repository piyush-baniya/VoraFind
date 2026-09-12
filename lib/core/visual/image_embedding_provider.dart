import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../semantic/neural_embedding_runtime.dart' show OnnxRuntimeException;
import '../semantic/vector_math.dart' show VectorMath;
import 'image_preprocessor.dart' show ImagePreprocessor;
import 'image_visual_models.dart';
import 'visual_onnx_runtime.dart' show VisionOnnxSession;

/// An embedding of one decoded image (raw RGB888 pixels at
/// `[ImageVisualDefaults.inputDimension]²`) into a fixed-dimensional local
/// feature vector.
///
/// This is the **only** thing the rest of VoraFind knows about image
/// embeddings; the ML runtime lives entirely behind implementations of this
/// interface (docs `similar-image-search.md` §Embedding provider). The image
/// coordinator and search layer never touch ML types — mirrors
/// [VisualFrameClassifier] and [EmbeddingProvider].
abstract interface class ImageEmbeddingProvider {
  /// Stable identity of the current image-feature model. Changing this (or the
  /// vector [dimensions]) invalidates every stored image embedding.
  String get modelId;

  /// Dimensionality of every returned vector.
  int get dimensions;

  /// True when the local model is available and [embed] may be called.
  bool get isAvailable;

  /// Produces one L2-normalized embedding for [imageRgbBytes] (a decoded
  /// image, `224×224×3` bytes row-major RGB).
  ///
  /// Must return a vector of exactly [dimensions] entries, or throw an
  /// [ImageEmbeddingException] (wrong input, wrong-dimension/zero/NaN output,
  /// runtime failure are all surfaced as exceptions — callers persist a
  /// durable failed status). Implementations may perform I/O (model load,
  /// inference).
  Future<List<double>> embed({required Uint8List imageRgbBytes});

  /// Releases any native/model resources. Releasing the only available
  /// provider marks the subsystem unavailable but is never destructive to the
  /// persisted index.
  Future<void> dispose();
}

/// Production wiring lives in `image_visual_providers.dart` and is the
/// [NeuralImageEmbeddingProvider]. This provider is an honest "nothing to run"
/// fallback for tests and for platforms where the native runtime cannot load;
/// the subsystem reports unavailable and the coordinator does no work (mirrors
/// [UnavailableEmbeddingProvider]).
class UnavailableImageEmbeddingProvider implements ImageEmbeddingProvider {
  const UnavailableImageEmbeddingProvider();

  @override
  String get modelId => 'unavailable';

  @override
  int get dimensions => ImageVisualDefaults.dimensions;

  @override
  bool get isAvailable => false;

  @override
  Future<List<double>> embed({required Uint8List imageRgbBytes}) async {
    throw const ImageEmbeddingException(ImageVisualErrorCode.unavailable);
  }

  @override
  Future<void> dispose() async {}
}

/// Runs the bundled sliced MobileNetV2 feature graph through ONNX Runtime
/// on-device, fully offline (docs `similar-image-search.md`). The model ships
/// in the APK; nothing is downloaded at runtime.
///
/// Assets are loaded lazily on the first [embed] (mirrors
/// [NeuralVisualFrameClassifier]): reporting available before the first load,
/// then flipping terminal on any bundled-asset or native-runtime failure so
/// the coordinator emits `unavailable` instead of retrying every image.
class NeuralImageEmbeddingProvider implements ImageEmbeddingProvider {
  /// [modelBytes] overrides the bundled asset for tests and for swapping in a
  /// future feature model without a rebuild.
  NeuralImageEmbeddingProvider({Uint8List? modelBytes})
    : _modelBytes = modelBytes; // ignore: prefer_initializing_formals

  final Uint8List? _modelBytes;

  /// Intra-op thread count for ONNX Runtime inference. Fixed: encodes a single
  /// 224×224 image at a time, and battery-conscious phones benefit more from
  /// modest parallelism than from squeezing milliseconds out of one pass
  /// (mirrors `NeuralVisualFrameClassifier._intraOpNumThreads`).
  static const int _intraOpNumThreads = 2;

  VisionOnnxSession? _session;
  Future<void>? _loading;
  bool _unavailable = false;

  @override
  String get modelId => ImageVisualDefaults.modelId;

  @override
  int get dimensions => ImageVisualDefaults.dimensions;

  /// Reports available until a model asset load or inference actually fails
  /// (mirrors the visual classifier's optimistic availability).
  @override
  bool get isAvailable => !_unavailable;

  @override
  Future<List<double>> embed({required Uint8List imageRgbBytes}) async {
    await _ensureLoaded();
    final session = _session!;
    Float32List features;
    try {
      final tensor = ImagePreprocessor.mobilenetNchw(rgbBytes: imageRgbBytes);
      features = await session.embed(tensor, dimension: dimensions);
    } on ArgumentError {
      throw const ImageEmbeddingException(ImageVisualErrorCode.invalidInput);
    } on OnnxRuntimeException {
      // Model mismatch or native failure — transient, retried after cooldown.
      throw const ImageEmbeddingException(ImageVisualErrorCode.failed);
    }
    if (features.length != dimensions) {
      throw const ImageEmbeddingException(ImageVisualErrorCode.invalidOutput);
    }
    // L2-normalize so stored and query vectors are comparable by cosine. The
    // model's pooling output is already unit-ish, but normalization makes the
    // vectors storage-stable regardless of model drift.
    final normalized = VectorMath.normalized(features);
    if (normalized == null) {
      throw const ImageEmbeddingException(ImageVisualErrorCode.invalidOutput);
    }
    return normalized;
  }

  @override
  Future<void> dispose() async {
    _session?.release();
    _session = null;
  }

  /// Resolves the shared session, loading bundled assets at most once even when
  /// several embeds race during startup.
  Future<void> _ensureLoaded() {
    if (_session != null) return Future.value(null);
    if (_unavailable) {
      return Future.error(
        const ImageEmbeddingException(ImageVisualErrorCode.unavailable),
      );
    }
    final inFlight = _loading;
    if (inFlight != null) return inFlight;
    final future = _load();
    _loading = future;
    return future;
  }

  Future<void> _load() async {
    try {
      final modelBytes =
          _modelBytes ??
          (await rootBundle.load(ImageVisualDefaults.modelAssetPath)).buffer
              .asUint8List();
      final session = VisionOnnxSession.create(
        modelBytes: modelBytes,
        intraOpNumThreads: _intraOpNumThreads,
      );
      _session = session;
    } catch (_) {
      // Missing/undecodable asset or a native runtime failure: the bundled
      // model cannot serve today, and retrying on every batch would burn
      // battery. Flip terminal — the coordinator reports `unavailable`.
      _unavailable = true;
      throw const ImageEmbeddingException(ImageVisualErrorCode.unavailable);
    } finally {
      _loading = null;
    }
  }
}

/// Deterministic first-byte-keyed image embedding used by tests and as a
/// reference implementation of the provider contract.
///
/// This is NOT a visual model — a frame's *first RGB byte* selects one
/// dedicated dimension, so identical inputs are cosine-1.0, distinct inputs are
/// orthogonal, and the whole pipeline (decode → embed → storage → retrieval →
/// ranking) is exercised end-to-end deterministically without a real model —
/// mirrors [DeterministicVisualFrameClassifier]'s preset and
/// [DeterministicEmbeddingProvider].
///
/// Properties:
/// * deterministic — identical input → identical vector;
/// * bounded — always [dimensions] finite doubles;
/// * an empty input yields a zero vector which the caller treats as
///   unsupported (matches production semantics).
class DeterministicImageEmbeddingProvider implements ImageEmbeddingProvider {
  const DeterministicImageEmbeddingProvider({
    this.dimensions = ImageVisualDefaults.dimensions,
  });

  @override
  final int dimensions;

  @override
  String get modelId => 'deterministic-image-$dimensions';

  @override
  bool get isAvailable => true;

  @override
  Future<List<double>> embed({required Uint8List imageRgbBytes}) async {
    final vector = List<double>.filled(dimensions, 0);
    if (imageRgbBytes.isEmpty) return vector; // zero vector — unsupported.
    final index = imageRgbBytes[0] % dimensions;
    vector[index] = 1;
    return vector; // unit vector — cosine == dot product, already normalized.
  }

  @override
  Future<void> dispose() async {}
}
