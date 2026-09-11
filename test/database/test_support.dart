import 'package:drift/native.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/platform/media_discovery_models.dart';

/// Opens a disposable in-memory database for tests.
AppDatabase inMemoryDb() => AppDatabase(NativeDatabase.memory());

/// Builds a canonical image record; [id] is the MediaStore `_ID` and the
/// stable key, so distinct records are easy to build.
MediaDiscoveryRecord buildRecord({
  int id = 1,
  ContentCategory category = ContentCategory.images,
  String volumeName = 'external_primary',
  String? displayName,
  String? mimeType,
  int? sizeBytes,
  int? dateAdded,
  int? dateModified,
  String? relativePath = 'DCIM/Camera/',
  String? bucketDisplayName = 'Camera',
  int? width = 1920,
  int? height = 1080,
  int? durationMs,
  String? title,
  String? artist,
  String? album,
  int? screenshotScore = 10,
  bool? isScreenshot = false,
  String? relinkSignature = 'sig-1',
  String? stableKey,
}) => MediaDiscoveryRecord(
  category: category,
  volumeName: volumeName,
  mediaStoreId: id,
  stableKey: stableKey ?? '$volumeName:$id',
  relinkSignature: relinkSignature,
  contentUri: 'content://media/$volumeName/${category.name}/media/$id',
  displayName: displayName ?? 'item_$id.${_ext(category)}',
  mimeType: mimeType ?? _mime(category),
  sizeBytes: sizeBytes ?? 1000 + id,
  dateAdded: dateAdded ?? 1000 + id,
  dateModified: dateModified ?? 2000 + id,
  relativePath: relativePath,
  bucketDisplayName: bucketDisplayName,
  width: width,
  height: height,
  durationMs: durationMs,
  title: title,
  artist: artist,
  album: album,
  screenshotScore: screenshotScore,
  isScreenshot: isScreenshot,
);

/// A media record with full audio metadata (for round-trip coverage).
MediaDiscoveryRecord buildAudioRecord({int id = 10}) => buildRecord(
  id: id,
  category: ContentCategory.audio,
  relinkSignature: 'sig-audio-$id',
  relativePath: 'Music/Albums/',
  bucketDisplayName: 'Albums',
  width: null,
  height: null,
  durationMs: 3 * 60 * 1000 + 15 * 1000,
  title: 'Song title',
  artist: 'The Artist',
  album: 'The Album',
);

/// Builds one wire batch event around [records].
DiscoveryBatchEvent buildBatch({
  required int sequence,
  required List<MediaDiscoveryRecord> records,
  bool hasMore = false,
  int? generationAfter,
  DiscoveryAccessScope accessScope = DiscoveryAccessScope.full,
}) => DiscoveryBatchEvent(
  sequence: sequence,
  category: records.isEmpty ? ContentCategory.images : records.first.category,
  volume: records.isEmpty ? 'external_primary' : records.first.volumeName,
  accessScope: accessScope,
  records: records,
  hasMore: hasMore,
  skippedCount: 0,
  generationAfter: generationAfter,
);

String _mime(ContentCategory category) => switch (category) {
  ContentCategory.images => 'image/jpeg',
  ContentCategory.videos => 'video/mp4',
  ContentCategory.audio => 'audio/mpeg',
  ContentCategory.documents => 'application/pdf',
};

String _ext(ContentCategory category) => switch (category) {
  ContentCategory.images => 'jpg',
  ContentCategory.videos => 'mp4',
  ContentCategory.audio => 'mp3',
  ContentCategory.documents => 'pdf',
};
