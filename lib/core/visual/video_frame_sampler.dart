import 'package:flutter/services.dart';

import 'visual_models.dart';

/// One downscaled video frame captured by the native sampler.
class SampledVideoFrame {
  const SampledVideoFrame({required this.frameTsMs, required this.rgbBytes});

  /// Milliseconds from the start of the video (MediaMetadataRetriever's
  /// timestamp units).
  final int frameTsMs;

  /// RGB888 pixel data, `inputDimension × inputDimension × 3` bytes
  /// (`[VisualDefaults.inputDimension]`), row-major.
  final Uint8List rgbBytes;
}

/// Result of sampling one video: the bounded set of frames plus the native
/// duration estimate.
class VideoFrameSampling {
  const VideoFrameSampling({
    required this.frames,
    this.durationMs,
    this.errorCode,
  });

  /// Sampled frames, at most [VisualDefaults.maxFramesPerVideo].
  final List<SampledVideoFrame> frames;

  /// Native duration estimate (milliseconds), when the platform reported one.
  final int? durationMs;

  /// Non-null when sampling failed *before* producing frames (corrupt or
  /// DRM-protected media). Per-frame failures are impossible by construction:
  /// a video either decodes or it does not.
  final String? errorCode;
}

/// Stable wire codes surfaced by the native sampler.
abstract final class VisualSamplerError {
  static const String unsupported = 'unsupported';
  static const String corrupt = 'corrupt';
  static const String denied = 'denied';
  static const String platformUnavailable = 'platformUnavailable';
}

/// Fixed target dimension of the native frame sampling.
const int _targetDimension = VisualDefaults.inputDimension;

/// Typed entry point to VoraFind's native Android video frame sampler.
///
/// Contract: [sampleFrames] runs on the native side off the UI thread, opens
/// the video once via MediaMetadataRetriever, extracts at most
/// [VisualDefaults.maxFramesPerVideo] uniformly-spaced frames downscaled to
/// `inputDimension×inputDimension`, and returns them as raw RGB888 so no
/// privacy-sensitive image bytes ever leave the device (privacy rules §8). A
/// corrupt or DRM-protected video yields [VisualSamplerError.corrupt] — never
/// an app crash (AGENTS.md §19).
abstract interface class VideoFrameSampler {
  Future<VideoFrameSampling> sampleFrames({
    required String contentUri,
    int maxFrames = VisualDefaults.maxFramesPerVideo,
  });
}

/// [VideoFrameSampler] backed by the `vorafind/video` method channel
/// ([VideoFrameBridge], Kotlin).
class MethodChannelVideoFrameSampler implements VideoFrameSampler {
  MethodChannelVideoFrameSampler({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Dart side of the `vorafind/video` method channel declared by
  /// [VideoFrameBridge].
  static const channelName = 'vorafind/video';

  final MethodChannel _channel;

  @override
  Future<VideoFrameSampling> sampleFrames({
    required String contentUri,
    int maxFrames = VisualDefaults.maxFramesPerVideo,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'sampleFrames',
        {
          'contentUri': contentUri,
          'maxFrames': maxFrames,
          'dimension': _targetDimension,
        },
      );
      if (raw == null) {
        return const VideoFrameSampling(
          frames: [],
          errorCode: VisualSamplerError.platformUnavailable,
        );
      }
      final duration =
          (raw['durationMs'] as int?) ?? (raw['durationMs'] as num?)?.toInt();
      final rawFrames = (raw['frames'] as List?) ?? const [];
      final frames = <SampledVideoFrame>[];
      for (final entry in rawFrames.cast<Map>()) {
        final ts = (entry['tsMs'] as int?) ?? (entry['tsMs'] as num?)?.toInt();
        final bytes = entry['rgb'] as Uint8List?;
        if (ts == null || bytes == null) continue;
        frames.add(SampledVideoFrame(frameTsMs: ts, rgbBytes: bytes));
      }
      return VideoFrameSampling(frames: frames, durationMs: duration);
    } on MissingPluginException {
      return const VideoFrameSampling(
        frames: [],
        errorCode: VisualSamplerError.platformUnavailable,
      );
    } on PlatformException catch (error) {
      return VideoFrameSampling(
        frames: [],
        errorCode: error.code.isEmpty ? VisualSamplerError.corrupt : error.code,
      );
    }
  }
}

/// Honest "nothing to sample" fallback for tests and non-Android hosts: the
/// coordinator reports [VisualRunStatus.unavailable] and skips the stage.
class UnavailableVideoFrameSampler implements VideoFrameSampler {
  const UnavailableVideoFrameSampler();

  @override
  Future<VideoFrameSampling> sampleFrames({
    required String contentUri,
    int maxFrames = VisualDefaults.maxFramesPerVideo,
  }) async {
    return const VideoFrameSampling(
      frames: [],
      errorCode: VisualSamplerError.platformUnavailable,
    );
  }
}
