import 'package:drift/drift.dart';

import '../platform/media_discovery_models.dart'
    show DiscoveryAccessScope, MediaDiscoveryRecord;
import 'app_database.dart';
import 'media_items_table.dart';

/// Maps between the discovery wire record ([MediaDiscoveryRecord]) and the
/// `media_items` Drift row ([MediaItems] / [MediaItemsCompanion]).
///
/// The mapping is one-way explicit: discovery values are persisted unchanged,
/// and only the indexing-state bookkeeping columns are added here. The relink
/// signature is stored verbatim — it is never recomputed at this layer.
class MediaItemMapper {
  const MediaItemMapper();

  /// Companion for the INSERT arm of an upsert: every column is set and the
  /// item starts with `metadataRevision = 1`, `indexingStatus = none`, and
  /// first/last-seen both equal to [nowSeconds].
  MediaItemsCompanion forInsert(
    MediaDiscoveryRecord record, {
    required int nowSeconds,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  }) => MediaItemsCompanion(
    stableKey: Value(record.stableKey),
    category: Value(record.category.name),
    volumeName: Value(record.volumeName),
    mediaStoreId: Value(record.mediaStoreId),
    contentUri: Value(record.contentUri),
    displayName: Value(record.displayName),
    title: Value<String?>(record.title),
    mimeType: Value<String?>(record.mimeType),
    sizeBytes: Value<int?>(record.sizeBytes),
    dateAdded: Value<int?>(record.dateAdded),
    dateModified: Value<int?>(record.dateModified),
    relativePath: Value<String?>(record.relativePath),
    bucketDisplayName: Value<String?>(record.bucketDisplayName),
    width: Value<int?>(record.width),
    height: Value<int?>(record.height),
    durationMs: Value<int?>(record.durationMs),
    artist: Value<String?>(record.artist),
    album: Value<String?>(record.album),
    albumArtist: const Value<String?>(null),
    trackNumber: const Value<int?>(null),
    discNumber: const Value<int?>(null),
    genre: const Value<String?>(null),
    screenshotScore: Value<int?>(record.screenshotScore),
    isScreenshot: Value<bool?>(record.isScreenshot),
    relinkSignature: Value<String?>(record.relinkSignature),
    firstDiscoveredAt: Value(nowSeconds),
    lastDiscoveredAt: Value(nowSeconds),
    lastIndexedGeneration: Value<int?>(generationAfter),
    metadataRevision: const Value(1),
    indexingStatus: const Value(IndexingStatus.none),
    lastSeenAccessScope: Value<String?>(accessScope?.name),
  );

  /// The `DO UPDATE SET` arm for an existing row.
  ///
  /// [existing] is the current database row in DSL form, so its columns are
  /// usable as expressions: `stableKey`, `firstDiscoveredAt`, and
  /// `indexingStatus` are intentionally absent from the SET list (preserved on
  /// update), and `metadataRevision` is bumped by referencing the old value.
  Insertable<MediaItem> forConflictUpdate(
    MediaItems existing,
    MediaDiscoveryRecord record, {
    required int nowSeconds,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  }) => MediaItemsCompanion.custom(
    category: Constant(record.category.name),
    volumeName: Constant(record.volumeName),
    mediaStoreId: Constant(record.mediaStoreId),
    contentUri: Constant(record.contentUri),
    displayName: Constant(record.displayName),
    title: _nullable<String>(record.title),
    mimeType: _nullable<String>(record.mimeType),
    sizeBytes: _nullable<int>(record.sizeBytes),
    dateAdded: _nullable<int>(record.dateAdded),
    dateModified: _nullable<int>(record.dateModified),
    relativePath: _nullable<String>(record.relativePath),
    bucketDisplayName: _nullable<String>(record.bucketDisplayName),
    width: _nullable<int>(record.width),
    height: _nullable<int>(record.height),
    durationMs: _nullable<int>(record.durationMs),
    artist: _nullable<String>(record.artist),
    album: _nullable<String>(record.album),
    albumArtist: _nullable<String>(null),
    trackNumber: _nullable<int>(null),
    discNumber: _nullable<int>(null),
    genre: _nullable<String>(null),
    screenshotScore: _nullable<int>(record.screenshotScore),
    isScreenshot: _nullable<bool>(record.isScreenshot),
    relinkSignature: _nullable<String>(record.relinkSignature),
    lastDiscoveredAt: Constant(nowSeconds),
    lastIndexedGeneration: _nullable<int>(generationAfter),
    metadataRevision: existing.metadataRevision + const Constant(1),
    lastSeenAccessScope: _nullable<String>(accessScope?.name),
  );

  /// A nullable SQL expression; null becomes a bound NULL parameter.
  Expression<T> _nullable<T extends Object>(T? value) => Variable<T>(value);
}
