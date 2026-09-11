import 'dart:math' as math;
import 'dart:typed_data';

import 'visual_models.dart';

/// Converts raw RGB888 pixels into the float `NCHW` tensor the bundled
/// MobileNetV2 expects, applying the ONNX Model Zoo's ImageNet normalization.
///
/// The model's zoo preprocessing is BGR-order with per-channel mean/std:
/// `(pixel - mean) / std` over values in `[0, 255]`:
///
/// * B channel: mean 103.53, std 57.375
/// * G channel: mean 116.28, std 57.12
/// * R channel: mean 123.675, std 58.395
///
/// This is the same convention verified against the real model in
/// `docs/video-visual-search.md` §Preprocessing. Pure function — deterministic
/// and trivially unit-testable.
abstract final class ImagePreprocessor {
  /// Returns `inputDimension × inputDimension × 3` floats in `CHW`, BGR order.
  static Float32List mobilenetNchw({
    required Uint8List rgbBytes,
    int dimension = VisualDefaults.inputDimension,
  }) {
    final expected = dimension * dimension * 3;
    if (rgbBytes.length != expected) {
      throw ArgumentError(
        'expected $expected RGB bytes for $dimension×$dimension, '
        'got ${rgbBytes.length}',
      );
    }
    final out = Float32List(expected);
    final pixels = dimension * dimension;
    for (var p = 0; p < pixels; p++) {
      final base = p * 3;
      final r = rgbBytes[base];
      final g = rgbBytes[base + 1];
      final b = rgbBytes[base + 2];
      // CHW: channel block `c` starts at c * pixels.
      out[p] = (b - 103.53) / 57.375;
      out[pixels + p] = (g - 116.28) / 57.12;
      out[pixels * 2 + p] = (r - 123.675) / 58.395;
    }
    return out;
  }
}

/// Stable softmax/top-K math shared by the classifier (`K` = logits).
abstract final class Softmax {
  /// Softmax over [logits] (must be non-empty) returning a probability vector
  /// of the same length.
  static Float32List apply(Float32List logits) {
    if (logits.isEmpty) throw ArgumentError('logits must be non-empty');
    var max = logits[0];
    for (final v in logits) {
      if (v > max) max = v;
    }
    final out = Float32List(logits.length);
    var sum = 0.0;
    for (var i = 0; i < logits.length; i++) {
      final exp = math.exp(logits[i] - max);
      out[i] = exp;
      sum += exp;
    }
    if (sum <= 0) {
      // Degenerate (all -inf): uniform distribution keeps processing safe.
      final uniform = 1.0 / logits.length;
      for (var i = 0; i < logits.length; i++) {
        out[i] = uniform;
      }
      return out;
    }
    for (var i = 0; i < logits.length; i++) {
      out[i] /= sum.toDouble();
    }
    return out;
  }
}
