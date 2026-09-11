import 'package:flutter/services.dart';

import 'content_access_models.dart' show ContentCategory;
import 'media_discovery_models.dart';

/// Typed entry point to VoraFind's native Android discovery layer.
///
/// Contract: one live session at a time; every [MediaDiscoveryRecord] is
/// delivered in a [DiscoveryBatchEvent] that the caller must [ackBatch] before
/// the next batch arrives (window 1). Application code depends on this
/// interface instead of touching channel wire strings directly.
abstract interface class MediaDiscovery {
  /// Typed discovery events. Subscribe before [startDiscovery], otherwise the
  /// native side refuses with `eventListenerNotAttached`.
  Stream<DiscoveryEvent> events();

  /// Starts a discovery session for [categories]. The caller checks
  /// [DiscoveryStartResult.accepted]; per-category outcomes (started/partial/
  /// unavailable) are reported in [DiscoveryStartResult.categories].
  /// When [volumes] is non-empty, only those MediaStore volumes are scanned.
  Future<DiscoveryStartResult> startDiscovery(
    List<ContentCategory> categories, {
    List<String>? volumes,
  });

  /// Reads the MediaStore generation token for one category/volume pair.
  /// Null means unknown/unsupported, which disables the unchanged fast-check.
  Future<int?> getGeneration(ContentCategory category, String volumeName);

  /// ACKs batch [sequence], allowing the scanner to emit the next batch.
  /// Returns false for unknown, duplicate, or stale sequences.
  Future<bool> ackBatch(int sequence);

  /// Cancels the running session. Safe to call at any time and idempotent.
  Future<bool> cancelDiscovery();

  /// Point-in-time scanner snapshot. Side-effect free.
  Future<DiscoveryStatus> getDiscoveryStatus();
}

/// [MediaDiscovery] backed by the `vorafind/indexing` method channel and the
/// `vorafind/indexing/events` event channel ([DiscoveryBridge], Kotlin).
class MethodChannelMediaDiscovery implements MediaDiscovery {
  MethodChannelMediaDiscovery({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel(indexingChannelName),
      _events = events ?? const EventChannel(eventsChannelName);

  /// Dart side of the `vorafind/indexing` method channel declared by
  /// [DiscoveryBridge] (Kotlin).
  static const indexingChannelName = 'vorafind/indexing';

  /// Dart side of the `vorafind/indexing/events` event channel declared by
  /// [DiscoveryBridge] (Kotlin).
  static const eventsChannelName = 'vorafind/indexing/events';

  final MethodChannel _channel;
  final EventChannel _events;

  @override
  Stream<DiscoveryEvent> events() => _events.receiveBroadcastStream().map(
    (raw) => DiscoveryEvent.fromJson(_mapOf(raw)),
  );

  @override
  Future<DiscoveryStartResult> startDiscovery(
    List<ContentCategory> categories, {
    List<String>? volumes,
  }) => _invoke('startDiscovery', {
    'categories': categories.map((category) => category.name).toList(),
    // Only include the filter when it is non-empty — the wire contract has no
    // "volumes" key otherwise.
    if (volumes != null && volumes.isNotEmpty)
      'volumes': volumes.toList(growable: false),
  }, (raw) => DiscoveryStartResult.fromJson(_mapOf(raw)));

  @override
  Future<int?> getGeneration(ContentCategory category, String volumeName) =>
      _invoke('getGeneration', {
        'category': category.name,
        'volumeName': volumeName,
      }, (raw) => _mapOf(raw)['generation'] as int?);

  @override
  Future<bool> ackBatch(int sequence) => Future.sync(() {
    if (sequence < 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Must be non-negative');
    }
    return _invoke('ackBatch', {'sequence': sequence}, (raw) => raw as bool);
  });

  @override
  Future<bool> cancelDiscovery() => _invoke('cancelDiscovery', null, (raw) {
    return raw as bool;
  });

  @override
  Future<DiscoveryStatus> getDiscoveryStatus() => _invoke(
    'getDiscoveryStatus',
    null,
    (raw) => DiscoveryStatus.fromJson(_mapOf(raw)),
  );

  Future<T> _invoke<T>(
    String method,
    Map<String, Object?>? arguments,
    T Function(Object?) decode,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, arguments);
      return decode(raw);
    } on PlatformException catch (error) {
      throw DiscoveryException.fromPlatformException(error);
    }
  }

  Map<String, dynamic> _mapOf(Object? raw) =>
      (raw as Map).cast<String, dynamic>();
}
