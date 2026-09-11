import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../semantic/neural_embedding_runtime.dart' show OnnxRuntimeException;

import 'image_preprocessor.dart';
import 'visual_models.dart';
import 'visual_onnx_runtime.dart';

/// Result of classifying one downscaled video frame.
class VisualFrameClassification {
  const VisualFrameClassification({required this.concepts});

  /// Distinct concepts, each at or above
  /// [VisualDefaults.minConceptConfidence], ordered by confidence descending.
  final List<VisualFrameConcept> concepts;
}

/// The **only** thing the rest of VoraFind knows about local image models; the
/// ONNX Runtime call happens entirely behind implementations of this interface
/// (docs `video-visual-search.md`). The coordinator and search layer never
/// touch ML types — mirrors [EmbeddingProvider].
abstract interface class VisualFrameClassifier {
  /// Stable identity of the current vision model. Changing it invalidates the
  /// whole visual index (rows are re-analyzed on the next run).
  String get modelId;

  /// True when the local model is available and [classify] may be called.
  bool get isAvailable;

  /// Classifies one frame's raw RGB888 pixels (inputDimension²×3 bytes).
  ///
  /// Must return concepts at or above [VisualDefaults.minConceptConfidence],
  /// or throw [VisualClassificationException] (never malformed output — the
  /// coordinator persists a durable failed status). May perform I/O (model
  /// load, inference).
  Future<VisualFrameClassification> classify({required Uint8List rgbBytes});

  /// Releases any native/model resources. Never destructive to the persisted
  /// index.
  Future<void> dispose();
}

/// Runs the bundled int8 MobileNetV2 through ONNX Runtime on-device, fully
/// offline (docs `video-visual-search.md`). The model and its ImageNet labels
/// ship in the APK; nothing is downloaded at runtime.
///
/// Assets are loaded lazily on the first [classify] (mirrors
/// [NeuralEmbeddingProvider]): reporting available before the first load, then
/// flipping terminal on any bundled-asset or native-runtime failure so the
/// coordinator emits `unavailable` instead of retrying every video.
class NeuralVisualFrameClassifier implements VisualFrameClassifier {
  /// [modelBytes] and [labels] override the bundled assets for tests and for
  /// swapping in a future vision model without a rebuild.
  NeuralVisualFrameClassifier({Uint8List? modelBytes, List<String>? labels})
    : _modelBytes = modelBytes, // ignore: prefer_initializing_formals
      _labels = labels; // ignore: prefer_initializing_formals

  final Uint8List? _modelBytes;
  final List<String>? _labels;

  /// Intra-op thread count for ONNX Runtime inference. Fixed: encodes a single
  /// 224×224 frame at a time, and battery-conscious phones benefit more from
  /// modest parallelism than from squeezing milliseconds out of one pass.
  static const int _intraOpNumThreads = 2;

  VisionOnnxSession? _session;
  List<String>? _loadedLabels;
  Future<void>? _loading;
  bool _unavailable = false;

  @override
  String get modelId => VisualDefaults.visualModelId;

  /// Reports available until a model asset load or inference actually fails
  /// (mirrors the neural embedding provider's optimistic availability).
  @override
  bool get isAvailable => !_unavailable;

  @override
  Future<VisualFrameClassification> classify({
    required Uint8List rgbBytes,
  }) async {
    await _ensureLoaded();
    final session = _session!;
    final labels = _loadedLabels!;
    Float32List logits;
    try {
      final tensor = ImagePreprocessor.mobilenetNchw(rgbBytes: rgbBytes);
      logits = await session.classify(tensor);
    } on ArgumentError {
      throw const VisualClassificationException(VisualErrorCode.invalidInput);
    } on OnnxRuntimeException {
      // Model mismatch or native failure — transient, retried after cooldown.
      throw const VisualClassificationException(VisualErrorCode.failed);
    }
    if (logits.length != labels.length) {
      throw const VisualClassificationException(VisualErrorCode.invalidOutput);
    }
    return VisualFrameClassification(
      concepts: _topConcepts(Softmax.apply(logits), labels),
    );
  }

  @override
  Future<void> dispose() async {
    _session?.release();
    _session = null;
  }

  /// Resolves the shared session, loading bundled assets at most once even when
  /// several classifies race during startup.
  Future<void> _ensureLoaded() {
    if (_session != null) return Future.value(null);
    if (_unavailable) {
      return Future.error(
        const VisualClassificationException(VisualErrorCode.unavailable),
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
          (await rootBundle.load(VisualDefaults.visualModelAssetPath)).buffer
              .asUint8List();
      final labels =
          _labels ?? await _loadLabels(VisualDefaults.visualLabelsAssetPath);
      final session = VisionOnnxSession.create(
        modelBytes: modelBytes,
        intraOpNumThreads: _intraOpNumThreads,
      );
      _loadedLabels = labels;
      _session = session;
    } catch (_) {
      // Missing/undecodable asset or a native runtime failure: the bundled
      // model cannot serve today, and retrying on every batch would burn
      // battery. Flip terminal — the coordinator reports `unavailable`.
      _unavailable = true;
      throw const VisualClassificationException(VisualErrorCode.unavailable);
    } finally {
      _loading = null;
    }
  }

  static Future<List<String>> _loadLabels(String assetPath) async {
    final text = await rootBundle.loadString(assetPath);
    final lines = text.split('\n');
    final labels = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // synset.txt lines are "<wordnet id>   <label text>"; keep only the
      // label text (the line number indexes the 1000-class output).
      final space = trimmed.indexOf(' ');
      labels.add(space > 0 ? trimmed.substring(space + 1).trim() : trimmed);
    }
    if (labels.length != 1000) {
      throw StateError('expected 1000 ImageNet labels, got ${labels.length}');
    }
    return labels;
  }

  /// Maps the softmax distribution to at-most-[VisualDefaults.topLabelsPerFrame]
  /// labels, projects them onto the curated concept vocabulary, and keeps
  /// concepts whose aggregated label confidence clears
  /// [VisualDefaults.minConceptConfidence], sorted descending.
  static List<VisualFrameConcept> _topConcepts(
    Float32List probabilities,
    List<String> labels,
  ) {
    final topIndices = _topKIndices(
      probabilities,
      VisualDefaults.topLabelsPerFrame,
    );
    final conceptConfidence = <String, double>{};
    for (final index in topIndices) {
      final label = labels[index];
      final confidence = probabilities[index];
      for (final concept in VisualConceptMap.conceptsForLabel(label)) {
        final current = conceptConfidence[concept];
        if (current == null || confidence > current) {
          conceptConfidence[concept] = confidence;
        }
      }
    }
    final result = <VisualFrameConcept>[
      for (final entry in conceptConfidence.entries)
        if (entry.value >= VisualDefaults.minConceptConfidence)
          VisualFrameConcept(concept: entry.key, confidenceLabel: entry.value),
    ]..sort((a, b) => b.confidenceLabel.compareTo(a.confidenceLabel));
    return result;
  }

  static List<int> _topKIndices(Float32List values, int k) {
    if (values.isEmpty) return const [];
    // Partial selection via repeated max scannings: K is tiny (8 ≤ 1000), so
    // the O(K·N) cost is bounded and the code stays allocation-free.
    final indices = <int>[];
    final used = Uint8List(values.length);
    final count = math.min(k, values.length);
    for (var n = 0; n < count; n++) {
      var best = -1;
      for (var i = 0; i < values.length; i++) {
        if (used[i] == 1) continue;
        if (best == -1 || values[i] > values[best]) best = i;
      }
      if (best == -1) break;
      used[best] = 1;
      indices.add(best);
    }
    return indices;
  }
}

/// Deterministic, vocabulary-driven classifier used by tests and as a
/// reference implementation of the provider contract.
///
/// [preset] maps a frame's *first RGB byte value* to a fixed concept list, so
/// the full pipeline (frame sampling → classification → storage → search →
/// ranking → explanations) is exercised end-to-end deterministically without a
/// real model — mirrors [DeterministicEmbeddingProvider].
class DeterministicVisualFrameClassifier implements VisualFrameClassifier {
  const DeterministicVisualFrameClassifier({this.preset = _defaultPreset});

  /// First-byte value → concepts. A frame whose first pixel's R value is in
  /// [preset] returns that entry deterministically; anything else yields no
  /// concepts. Fixtures build frames with `Uint8List.filled(count, byte)`.
  final Map<int, List<VisualFrameConcept>> preset;

  static const _defaultPreset = <int, List<VisualFrameConcept>>{
    0x10: [VisualFrameConcept(concept: 'mountain', confidenceLabel: 0.9)],
    0x20: [VisualFrameConcept(concept: 'beach', confidenceLabel: 0.85)],
    0x30: [VisualFrameConcept(concept: 'car', confidenceLabel: 0.92)],
    0x40: [VisualFrameConcept(concept: 'dog', confidenceLabel: 0.88)],
    0x50: [VisualFrameConcept(concept: 'person', confidenceLabel: 0.8)],
    0x60: [VisualFrameConcept(concept: 'laptop', confidenceLabel: 0.82)],
    0x70: [VisualFrameConcept(concept: 'snow', confidenceLabel: 0.7)],
    0x80: [
      VisualFrameConcept(concept: 'mountain', confidenceLabel: 0.6),
      VisualFrameConcept(concept: 'beach', confidenceLabel: 0.55),
    ],
  };

  @override
  String get modelId => 'deterministic-visual';

  @override
  bool get isAvailable => true;

  @override
  Future<VisualFrameClassification> classify({
    required Uint8List rgbBytes,
  }) async {
    final key = rgbBytes.isEmpty ? -1 : rgbBytes[0];
    final concepts = preset[key] ?? const <VisualFrameConcept>[];
    final sorted = [...concepts]
      ..sort((a, b) => b.confidenceLabel.compareTo(a.confidenceLabel));
    return VisualFrameClassification(concepts: sorted);
  }

  @override
  Future<void> dispose() async {}
}
