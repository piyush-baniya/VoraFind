import 'package:flutter/services.dart';

import 'image_visual_models.dart';

/// One decoded image consulted for a similarity search or for index-time
/// embedding.
class ImagePixelRead {
  const ImagePixelRead({
    required this.width,
    required this.height,
    required this.rgbBytes,
    this.errorCode,
  });

  final int width;
  final int height;

  /// RGB888 pixel data, `width × height × 3` bytes row-major.
  final Uint8List rgbBytes;

  /// Non-null when the platform could not decode the content URI (denied,
  /// corrupt, or the platform became unavailable).
  final String? errorCode;
}

/// A small PNG preview of the reference image for the similar-images screen.
class ImagePixelPng {
  const ImagePixelPng({required this.bytes, this.errorCode});

  /// PNG-encoded bytes renderable with `Image.memory`.
  final Uint8List bytes;

  /// Non-null when the platform could not decode the content URI.
  final String? errorCode;
}

/// Result of the system image picker (`ACTION_GET_CONTENT`, no permission).
class ImagePixelPick {
  const ImagePixelPick({this.contentUri, this.errorCode});

  /// Content URI the user selected; null when [errorCode] is set.
  final String? contentUri;

  /// Non-null when the picker was cancelled or failed.
  final String? errorCode;
}

/// Stable wire codes surfaced by the native pixel bridge.
abstract final class ImagePixelError {
  static const String unsupported = 'unsupported';
  static const String corrupt = 'corrupt';
  static const String denied = 'denied';
  static const String cancelled = 'cancelled';
  static const String invalidContentUri = 'invalidContentUri';
  static const String platformUnavailable = 'platformUnavailable';
}

/// Typed entry point to VoraFind's native Android image pixel access.
///
/// Contract: decoding runs on the native side off the UI thread, opens the
/// content URI once, and returns raw RGB/SVG bytes so no privacy-sensitive
/// image bytes ever leave the device (privacy rules §8). A corrupt or denied
/// image yields a stable error code — never an app crash (AGENTS.md §19).
/// No read permission is needed: the platform reads via the MediaStore content
/// URIs the app already has access to.
abstract interface class ImagePixelSource {
  /// Decodes [contentUri] to an exact `dimension × dimension` RGB sample for
  /// model input (covers MediaStore URIs and `pickImage` results).
  Future<ImagePixelRead> readImageRgb({
    required String contentUri,
    int dimension = ImageVisualDefaults.inputDimension,
  });

  /// Decodes [contentUri] to a bounded square PNG preview.
  Future<ImagePixelPng> readImagePng({
    required String contentUri,
    int maxDimension = 384,
  });

  /// Launches the system image picker. Returns the selected content URI or an
  /// error code (`cancelled` when the user backed out).
  Future<ImagePixelPick> pickImage();
}

/// [ImagePixelSource] backed by the `vorafind/image` method channel
/// ([ImageVisualBridge], Kotlin).
class MethodChannelImagePixelSource implements ImagePixelSource {
  MethodChannelImagePixelSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Dart side of the `vorafind/image` method channel declared by
  /// [ImageVisualBridge].
  static const channelName = 'vorafind/image';

  final MethodChannel _channel;

  @override
  Future<ImagePixelRead> readImageRgb({
    required String contentUri,
    int dimension = ImageVisualDefaults.inputDimension,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'readImageRgb',
        {'contentUri': contentUri, 'dimension': dimension},
      );
      if (raw == null) {
        return ImagePixelRead(
          width: 0,
          height: 0,
          rgbBytes: Uint8List(0),
          errorCode: ImagePixelError.platformUnavailable,
        );
      }
      final width = (raw['width'] as int?) ?? 0;
      final height = (raw['height'] as int?) ?? 0;
      final rgb = raw['rgb'] as Uint8List? ?? Uint8List(0);
      return ImagePixelRead(width: width, height: height, rgbBytes: rgb);
    } on MissingPluginException {
      return ImagePixelRead(
        width: 0,
        height: 0,
        rgbBytes: Uint8List(0),
        errorCode: ImagePixelError.platformUnavailable,
      );
    } on PlatformException catch (error) {
      return ImagePixelRead(
        width: 0,
        height: 0,
        rgbBytes: Uint8List(0),
        errorCode: error.code.isEmpty ? ImagePixelError.corrupt : error.code,
      );
    }
  }

  @override
  Future<ImagePixelPng> readImagePng({
    required String contentUri,
    int maxDimension = 384,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'readImagePng',
        {'contentUri': contentUri, 'maxDimension': maxDimension},
      );
      if (raw == null) {
        return ImagePixelPng(
          bytes: Uint8List(0),
          errorCode: ImagePixelError.platformUnavailable,
        );
      }
      return ImagePixelPng(bytes: raw['bytes'] as Uint8List? ?? Uint8List(0));
    } on MissingPluginException {
      return ImagePixelPng(
        bytes: Uint8List(0),
        errorCode: ImagePixelError.platformUnavailable,
      );
    } on PlatformException catch (error) {
      return ImagePixelPng(
        bytes: Uint8List(0),
        errorCode: error.code.isEmpty ? ImagePixelError.corrupt : error.code,
      );
    }
  }

  @override
  Future<ImagePixelPick> pickImage() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('pickImage');
      if (raw == null) {
        return const ImagePixelPick(errorCode: ImagePixelError.cancelled);
      }
      final uri = raw['uri'] as String?;
      if (uri == null || uri.isEmpty) {
        return const ImagePixelPick(errorCode: ImagePixelError.cancelled);
      }
      return ImagePixelPick(contentUri: uri);
    } on MissingPluginException {
      return const ImagePixelPick(
        errorCode: ImagePixelError.platformUnavailable,
      );
    } on PlatformException catch (error) {
      return ImagePixelPick(errorCode: error.code);
    }
  }
}

/// Honest "nothing to read" fallback for tests and non-Android hosts: the
/// coordinator reports [ImageVisualRunStatus.unavailable] and skips the stage.
class UnavailableImagePixelSource implements ImagePixelSource {
  const UnavailableImagePixelSource();

  @override
  Future<ImagePixelRead> readImageRgb({
    required String contentUri,
    int dimension = ImageVisualDefaults.inputDimension,
  }) async {
    return ImagePixelRead(
      width: 0,
      height: 0,
      rgbBytes: Uint8List(0),
      errorCode: ImagePixelError.platformUnavailable,
    );
  }

  @override
  Future<ImagePixelPng> readImagePng({
    required String contentUri,
    int maxDimension = 384,
  }) async {
    return ImagePixelPng(
      bytes: Uint8List(0),
      errorCode: ImagePixelError.platformUnavailable,
    );
  }

  @override
  Future<ImagePixelPick> pickImage() async {
    return const ImagePixelPick(errorCode: ImagePixelError.platformUnavailable);
  }
}
