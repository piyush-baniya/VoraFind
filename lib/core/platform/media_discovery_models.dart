import 'package:flutter/services.dart';

import 'content_access_models.dart' show ContentCategory;

/// Scanner lifecycle state. Wire values match the Kotlin enum (DiscoveryState).
enum DiscoveryLifecycleState {
  idle,
  running,
  completed,
  cancelled,
  failed;

  static DiscoveryLifecycleState fromWire(String value) => values.firstWhere(
    (state) => state.name == value,
    orElse: () => throw FormatException('Unknown discovery state: $value'),
  );
}

/// Scope under which a category's MediaStore view is readable.
enum DiscoveryAccessScope {
  full,
  partial;

  static DiscoveryAccessScope fromWire(String value) => values.firstWhere(
    (scope) => scope.name == value,
    orElse: () => throw FormatException('Unknown access scope: $value'),
  );
}

/// What happened to one requested category at `startDiscovery` time.
enum CategoryStartStatus {
  started,
  partial,
  unavailable;

  static CategoryStartStatus fromWire(String value) => values.firstWhere(
    (status) => status.name == value,
    orElse: () =>
        throw FormatException('Unknown category start status: $value'),
  );
}

/// One normalized MediaStore discovery record.
///
/// This is discovery metadata only — never file bytes, thumbnails, or OCR.
/// [stableKey] is the primary identity (`volumeName:mediaStoreId`) and
/// [relinkSignature] survives MediaStore rebuilds. Screenshot fields are
/// non-authoritative hints present only for image records. Wire keys mirror
/// the Kotlin `MediaDiscoveryRecord.toMap()` contract.
class MediaDiscoveryRecord {
  const MediaDiscoveryRecord({
    required this.category,
    required this.volumeName,
    required this.mediaStoreId,
    required this.stableKey,
    required this.relinkSignature,
    required this.contentUri,
    required this.displayName,
    required this.mimeType,
    required this.sizeBytes,
    required this.dateAdded,
    required this.dateModified,
    required this.relativePath,
    required this.bucketDisplayName,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.title,
    required this.artist,
    required this.album,
    required this.screenshotScore,
    required this.isScreenshot,
  });

  factory MediaDiscoveryRecord.fromJson(Map<String, dynamic> json) {
    final category = ContentCategory.fromWire(json['category'] as String);
    return MediaDiscoveryRecord(
      category: category,
      volumeName: json['volumeName'] as String,
      mediaStoreId: json['mediaStoreId'] as int,
      stableKey: json['stableKey'] as String,
      relinkSignature: json['relinkSignature'] as String?,
      contentUri: json['contentUri'] as String,
      displayName: json['displayName'] as String,
      mimeType: json['mimeType'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      dateAdded: (json['dateAdded'] as num?)?.toInt(),
      dateModified: (json['dateModified'] as num?)?.toInt(),
      relativePath: json['relativePath'] as String?,
      bucketDisplayName: json['bucketDisplayName'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      screenshotScore: json['screenshotScore'] as int?,
      isScreenshot: json['isScreenshot'] as bool?,
    );
  }

  final ContentCategory category;
  final String volumeName;
  final int mediaStoreId;
  final String stableKey;
  final String? relinkSignature;
  final String contentUri;
  final String displayName;
  final String? mimeType;
  final int? sizeBytes;
  final int? dateAdded;
  final int? dateModified;
  final String? relativePath;
  final String? bucketDisplayName;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? title;
  final String? artist;
  final String? album;
  final int? screenshotScore;
  final bool? isScreenshot;
}

/// Per-category outcome surfaced right after `startDiscovery`.
class StartCategoryStatus {
  const StartCategoryStatus({
    required this.category,
    required this.status,
    required this.accessScope,
  });

  factory StartCategoryStatus.fromJson(Map<String, dynamic> json) =>
      StartCategoryStatus(
        category: ContentCategory.fromWire(json['category'] as String),
        status: CategoryStartStatus.fromWire(json['status'] as String),
        accessScope: json['accessScope'] == null
            ? null
            : DiscoveryAccessScope.fromWire(json['accessScope'] as String),
      );

  final ContentCategory category;
  final CategoryStartStatus status;
  final DiscoveryAccessScope? accessScope;
}

/// Result of `startDiscovery`. When [accepted] is false, [code] is a
/// user-safe refusal reason (e.g. `busy`, `eventListenerNotAttached`).
class DiscoveryStartResult {
  const DiscoveryStartResult({
    required this.accepted,
    required this.contractVersion,
    required this.code,
    required this.categories,
  });

  factory DiscoveryStartResult.fromJson(Map<String, dynamic> json) =>
      DiscoveryStartResult(
        accepted: json['accepted'] as bool,
        contractVersion: json['contractVersion'] as int,
        code: json['code'] as String?,
        categories: (json['categories'] as List<dynamic>)
            .map(
              (entry) => StartCategoryStatus.fromJson(
                (entry as Map).cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
      );

  final bool accepted;
  final int contractVersion;
  final String? code;
  final List<StartCategoryStatus> categories;
}

/// Point-in-time snapshot for `getDiscoveryStatus`.
class DiscoveryStatus {
  const DiscoveryStatus({
    required this.state,
    required this.currentCategory,
    required this.currentVolume,
    required this.sequence,
    required this.batchesSent,
    required this.recordsDiscovered,
    required this.skippedRecords,
    required this.lastError,
  });

  factory DiscoveryStatus.fromJson(Map<String, dynamic> json) =>
      DiscoveryStatus(
        state: DiscoveryLifecycleState.fromWire(json['state'] as String),
        currentCategory: json['currentCategory'] as String?,
        currentVolume: json['currentVolume'] as String?,
        sequence: json['sequence'] as int,
        batchesSent: json['batchesSent'] as int,
        recordsDiscovered: json['recordsDiscovered'] as int,
        skippedRecords: json['skippedRecords'] as int,
        lastError: json['lastError'] as String?,
      );

  final DiscoveryLifecycleState state;
  final String? currentCategory;
  final String? currentVolume;
  final int sequence;
  final int batchesSent;
  final int recordsDiscovered;
  final int skippedRecords;
  final String? lastError;
}

/// Typed discovery events pushed from the Dart `vorafind/indexing/events`
/// EventChannel. Each decoded event is a sealed subtype; an unknown wire type
/// raises [FormatException] so the UI never silently drops events.
sealed class DiscoveryEvent {
  const DiscoveryEvent();

  static DiscoveryEvent fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'discoveryStarted' => DiscoveryStartedEvent.fromJson(json),
      'discoveryBatch' => DiscoveryBatchEvent.fromJson(json),
      'discoveryProgress' => DiscoveryProgressEvent.fromJson(json),
      'discoveryCompleted' => DiscoveryCompletedEvent.fromJson(json),
      'discoveryCancelled' => DiscoveryCancelledEvent.fromJson(json),
      'discoveryError' => DiscoveryErrorEvent.fromJson(json),
      _ => throw FormatException('Unknown discovery event type: $type'),
    };
  }
}

/// One category/volume scan began.
class DiscoveryStartedEvent extends DiscoveryEvent {
  const DiscoveryStartedEvent({
    required this.category,
    required this.volume,
    required this.accessScope,
  });

  factory DiscoveryStartedEvent.fromJson(Map<String, dynamic> json) =>
      DiscoveryStartedEvent(
        category: ContentCategory.fromWire(json['category'] as String),
        volume: json['volume'] as String,
        accessScope: DiscoveryAccessScope.fromWire(
          json['accessScope'] as String,
        ),
      );

  final ContentCategory category;
  final String volume;
  final DiscoveryAccessScope accessScope;
}

/// One bounded batch of records awaiting an explicit ACK (window 1).
class DiscoveryBatchEvent extends DiscoveryEvent {
  const DiscoveryBatchEvent({
    required this.sequence,
    required this.category,
    required this.volume,
    required this.accessScope,
    required this.records,
    required this.hasMore,
    required this.skippedCount,
    required this.generationAfter,
  });

  factory DiscoveryBatchEvent.fromJson(Map<String, dynamic> json) =>
      DiscoveryBatchEvent(
        sequence: json['sequence'] as int,
        category: ContentCategory.fromWire(json['category'] as String),
        volume: json['volume'] as String,
        accessScope: DiscoveryAccessScope.fromWire(
          json['accessScope'] as String,
        ),
        records: (json['records'] as List<dynamic>)
            .map(
              (entry) => MediaDiscoveryRecord.fromJson(
                (entry as Map).cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
        hasMore: json['hasMore'] as bool,
        skippedCount: json['skippedCount'] as int,
        generationAfter: (json['generationAfter'] as num?)?.toInt(),
      );

  final int sequence;
  final ContentCategory category;
  final String volume;
  final DiscoveryAccessScope accessScope;
  final List<MediaDiscoveryRecord> records;
  final bool hasMore;
  final int skippedCount;
  final int? generationAfter;
}

/// Emitted after each ACKed batch with running totals.
class DiscoveryProgressEvent extends DiscoveryEvent {
  const DiscoveryProgressEvent({
    required this.sequence,
    required this.category,
    required this.volume,
    required this.accessScope,
    required this.recordsDiscovered,
    required this.skippedRecords,
    required this.batchesSent,
    required this.batchesRemaining,
  });

  factory DiscoveryProgressEvent.fromJson(Map<String, dynamic> json) =>
      DiscoveryProgressEvent(
        sequence: json['sequence'] as int,
        category: ContentCategory.fromWire(json['category'] as String),
        volume: json['volume'] as String,
        accessScope: DiscoveryAccessScope.fromWire(
          json['accessScope'] as String,
        ),
        recordsDiscovered: json['recordsDiscovered'] as int,
        skippedRecords: json['skippedRecords'] as int,
        batchesSent: json['batchesSent'] as int,
        batchesRemaining: json['batchesRemaining'] as int,
      );

  final int sequence;
  final ContentCategory category;
  final String volume;
  final DiscoveryAccessScope accessScope;
  final int recordsDiscovered;
  final int skippedRecords;
  final int batchesSent;
  final int batchesRemaining;
}

/// The whole session finished cleanly.
class DiscoveryCompletedEvent extends DiscoveryEvent {
  const DiscoveryCompletedEvent({
    required this.recordsDiscovered,
    required this.skippedRecords,
    required this.batchesSent,
    required this.categories,
    required this.volumes,
  });

  factory DiscoveryCompletedEvent.fromJson(Map<String, dynamic> json) =>
      DiscoveryCompletedEvent(
        recordsDiscovered: json['recordsDiscovered'] as int,
        skippedRecords: json['skippedRecords'] as int,
        batchesSent: json['batchesSent'] as int,
        categories: (json['categories'] as List<dynamic>)
            .map((value) => ContentCategory.fromWire(value as String))
            .toList(growable: false),
        volumes: (json['volumes'] as List<dynamic>).cast<String>(),
      );

  final int recordsDiscovered;
  final int skippedRecords;
  final int batchesSent;
  final List<ContentCategory> categories;
  final List<String> volumes;
}

/// The session was cancelled (always via `cancelDiscovery`, never inferred).
class DiscoveryCancelledEvent extends DiscoveryEvent {
  const DiscoveryCancelledEvent({
    required this.recordsDiscovered,
    required this.skippedRecords,
    required this.batchesSent,
  });

  factory DiscoveryCancelledEvent.fromJson(Map<String, dynamic> json) =>
      DiscoveryCancelledEvent(
        recordsDiscovered: json['recordsDiscovered'] as int,
        skippedRecords: json['skippedRecords'] as int,
        batchesSent: json['batchesSent'] as int,
      );

  final int recordsDiscovered;
  final int skippedRecords;
  final int batchesSent;
}

/// A scanner-level failure ended the session. [message] never contains file
/// contents or private path data.
class DiscoveryErrorEvent extends DiscoveryEvent {
  const DiscoveryErrorEvent({required this.code, required this.message});

  factory DiscoveryErrorEvent.fromJson(Map<String, dynamic> json) =>
      DiscoveryErrorEvent(
        code: json['code'] as String,
        message: json['message'] as String,
      );

  final String code;
  final String message;
}

/// User-safe error from the discovery layer. Codes mirror the Kotlin bridge:
/// invalidArguments, discoveryStartFailed. Scanner failures arrive through
/// [DiscoveryErrorEvent] instead.
class DiscoveryException implements Exception {
  const DiscoveryException(this.code, this.message);

  factory DiscoveryException.fromPlatformException(PlatformException error) =>
      DiscoveryException(error.code, error.message ?? error.code);

  final String code;
  final String message;

  @override
  String toString() => 'DiscoveryException($code): $message';
}
