import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/visual/image_pixel_source.dart';
import '../../../core/visual/image_visual_providers.dart'
    show imagePixelSourceProvider;

/// Bounded in-memory cache of small PNG thumbnail bytes, keyed by content URI.
///
/// Thumbnails are derived data never persisted: the native layer decodes at
/// most [maxDimension] px, the LRU cap keeps memory bounded regardless of
/// library size (AGENTS.md §12), and no user content ever leaves the device
/// (privacy rules §8). Failed decodes are never cached.
class VoraImageCache {
  VoraImageCache({required this.source, this.maxEntries = 96});

  final ImagePixelSource source;
  final int maxEntries;

  final _entries = <String, Uint8List>{};
  final _inflight = <String, Future<Uint8List?>>{};

  /// PNG bytes for [contentUri], or null when not cached.
  Uint8List? peek(String contentUri) => _entries[contentUri];

  /// Fetches (or returns cached) small PNG bytes for [contentUri]. One decode
  /// is shared per content URI so a burst of identical tiles never fans out N
  /// native decodes. Returns null on failure/unsupported.
  Future<Uint8List?> load(String contentUri, {int maxDimension = 384}) {
    final cached = _entries[contentUri];
    if (cached != null) {
      // Re-touch so the entry counts as recently used.
      _entries.remove(contentUri);
      _entries[contentUri] = cached;
      return Future.value(cached);
    }

    final inFlight = _inflight[contentUri];
    if (inFlight != null) return inFlight;

    final tracked = source
        .readImagePng(contentUri: contentUri, maxDimension: maxDimension)
        .then((result) {
          _inflight.remove(contentUri);
          final bytes = result.bytes;
          if (bytes.isEmpty) return null;
          put(contentUri, bytes);
          return bytes;
        });
    _inflight[contentUri] = tracked;
    return tracked;
  }

  void put(String contentUri, Uint8List bytes) {
    if (bytes.isEmpty) return;
    _entries.remove(contentUri);
    _entries[contentUri] = bytes;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Clears cached and in-flight work (e.g. when the native bridge becomes
  /// unavailable or tests need a pristine state).
  void invalidate() {
    _entries.clear();
    _inflight.clear();
  }
}

/// App-wide thumbnail cache. Wired to the native pixel bridge so widget tests
/// can override [imagePixelSourceProvider] and the cache follows.
final voraImageCacheProvider = Provider<VoraImageCache>((ref) {
  return VoraImageCache(source: ref.watch(imagePixelSourceProvider));
});
