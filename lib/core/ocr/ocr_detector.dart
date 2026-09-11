import 'package:flutter/services.dart';

import 'ocr_models.dart';

/// Typed entry point to VoraFind's native Android OCR layer.
///
/// Contract: recognition runs on the native side on a dedicated worker thread,
/// at most one call in flight at a time (a concurrent call is rejected with
/// [OcrErrorCode.busy]). Every call stays on the device (privacy rules §8).
/// Application code depends on this interface instead of touching channel wire
/// strings directly.
abstract interface class OcrDetector {
  /// Recognizes text in the image behind [contentUri] using the on-device
  /// recognizer.
  ///
  /// [maxWidth] caps the decoded image dimension: the native side applies a
  /// power-of-two downsample so the decoder never sees a full sensor-resolution
  /// bitmap. Throws [OcrRecognitionException] on any failure. An empty string
  /// is a valid "no text found" success.
  Future<OcrRecognitionResult> recognizeText(
    String contentUri, {
    int? maxWidth,
  });
}

/// [OcrDetector] backed by the `vorafind/ocr` method channel ([OcrBridge],
/// Kotlin).
class MethodChannelOcrDetector implements OcrDetector {
  MethodChannelOcrDetector({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Dart side of the `vorafind/ocr` method channel declared by [OcrBridge].
  static const channelName = 'vorafind/ocr';

  final MethodChannel _channel;

  @override
  Future<OcrRecognitionResult> recognizeText(
    String contentUri, {
    int? maxWidth,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'recognizeText',
        {'contentUri': contentUri, 'maxWidth': ?maxWidth},
      );
      final text = (raw?['text'] as String?) ?? '';
      return OcrRecognitionResult(text: text);
    } on MissingPluginException {
      throw OcrRecognitionException(
        code: OcrErrorCode.platformUnavailable,
        message: 'OCR is not available on this platform.',
      );
    } on PlatformException catch (error) {
      throw OcrRecognitionException(
        code: OcrErrorCode.fromWire(error.code),
        message: error.message,
      );
    }
  }
}
