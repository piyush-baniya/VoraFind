import 'package:drift/drift.dart';

import '../platform/content_access_models.dart' show ContentCategory;
import '../platform/media_discovery_models.dart'
    show DiscoveryAccessScope, MediaDiscoveryRecord;
import 'app_database.dart';
import 'media_item_mapper.dart';

/// Snapshot of the persisted media index.
class MediaIndexStats {
  const MediaIndexStats({
    required this.total,
    required this.byCategory,
    required this.volumeCount,
  });

  /// Total indexed rows.
  final int total;

  /// Indexed rows grouped by content category.
  final Map<ContentCategory, int> byCategory;

  /// Distinct volumes represented in the index.
  final int volumeCount;

  int countOf(ContentCategory category) => byCategory[category] ?? 0;
}

/// One page of indexed rows in MediaStore `_ID` order — the shape deletion
/// reconciliation consumes.
class IndexedMediaId {
  const IndexedMediaId({required this.stableKey, required this.mediaStoreId});

  final String stableKey;
  final int mediaStoreId;
}

/// Result of a changed-only upsert. [unchanged] rows were skipped entirely
/// (no write at all): they still count toward the persisted batch total.
class UpsertBatchDelta {
  const UpsertBatchDelta({
    required this.inserted,
    required this.updated,
    required this.unchanged,
  });

  final int inserted;
  final int updated;
  final int unchanged;

  int get total => inserted + updated + unchanged;
}

/// Durable per-unit synchronization checkpoint (one row in `index_state`).
class SyncCheckpoint {
  const SyncCheckpoint({
    required this.category,
    required this.volumeName,
    required this.lastGeneration,
    required this.lastAccessScope,
    required this.lastSyncAt,
    required this.lastResult,
  });

  final ContentCategory category;
  final String volumeName;

  /// MediaStore generation token; null when unsupported or unknown.
  final int? lastGeneration;

  /// Scope the checkpoint was taken under. Only a full-scope checkpoint may be
  /// reused for the unchanged fast-check or authorize deletion.
  final DiscoveryAccessScope lastAccessScope;

  final int lastSyncAt;

  /// Wire value of the previous run's result kind.
  final String lastResult;
}

/// Data-access boundary for the durable media index.
///
/// The UI and orchestration code depend on this interface — never on Drift
/// tables directly. Writes are idempotent: any number of upserts of the same
/// [MediaDiscoveryRecord.stableKey] produce exactly one row.
abstract interface class MediaRepository {
  /// Idempotently persists one record. `nowSeconds` is injectable so tests can
  /// assert first/last-seen behavior deterministically.
  Future<void> upsert(
    MediaDiscoveryRecord record, {
    int? nowSeconds,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  });

  /// Persists a discovery batch in one SQLite transaction. When every record
  /// succeeds the transaction commits and the written row count is returned;
  /// when anything fails the whole batch rolls back and the error propagates
  /// (the caller must not ACK the discovery batch).
  Future<int> upsertBatch(
    Iterable<MediaDiscoveryRecord> records, {
    int? nowSeconds,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  });

  Future<MediaItem?> fetchByStableKey(String stableKey);

  Future<List<MediaItem>> fetchByStableKeys(Iterable<String> stableKeys);

  /// Total rows in the index.
  Future<int> count();

  /// Counts broken down by category plus distinct volumes.
  Future<MediaIndexStats> stats();

  /// Removes one item. Returns true when a row was deleted, false when the
  /// stable key was not present.
  Future<bool> deleteByStableKey(String stableKey);

  /// Removes every row whose stable key is in [stableKeys]. Chunked internally
  /// to bound each DELETE statement's size.
  Future<void> deleteByStableKeys(Iterable<String> stableKeys);

  /// Pages over [category]/[volumeName] rows in MediaStore `_ID` order, for
  /// deletion reconciliation. Bounded by [limit]; pass the previous page's last
  /// id as [afterId].
  Future<List<IndexedMediaId>> fetchIndexedPage({
    required ContentCategory category,
    required String volumeName,
    int afterId = 0,
    int limit = 500,
  });

  /// Inserts new rows and updates rows whose discovery content changed,
  /// skipping rows that carry identical content. Unchanged rows are not
  /// written at all — no revision bump, no timestamp rewrite.
  Future<UpsertBatchDelta> upsertBatchChanged(
    Iterable<MediaDiscoveryRecord> records, {
    int? nowSeconds,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  });

  Future<SyncCheckpoint?> getSyncCheckpoint(
    ContentCategory category,
    String volumeName,
  );

  Future<void> saveSyncCheckpoint(SyncCheckpoint checkpoint);

  /// Clears the entire local media index. Explicitly requested only.
  Future<void> clearAll();
}

/// [MediaRepository] backed by [AppDatabase].
class DriftMediaRepository implements MediaRepository {
  DriftMediaRepository(this._db, {this._mapper = const MediaItemMapper()});

  final AppDatabase _db;
  final MediaItemMapper _mapper;

  @override
  Future<void> upsert(
    MediaDiscoveryRecord record, {
    int? nowSeconds,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  }) async {
    final now = nowSeconds ?? _nowSeconds();
    await _upsertOne(
      record,
      now: now,
      generationAfter: generationAfter,
      accessScope: accessScope,
    );
  }

  @override
  Future<int> upsertBatch(
    Iterable<MediaDiscoveryRecord> records, {
    int? nowSeconds,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  }) async {
    final now = nowSeconds ?? _nowSeconds();
    final snapshot = List<MediaDiscoveryRecord>.of(records);
    return _db.transaction(() async {
      for (final record in snapshot) {
        await _upsertOne(
          record,
          now: now,
          generationAfter: generationAfter,
          accessScope: accessScope,
        );
      }
      return snapshot.length;
    });
  }

  Future<void> _upsertOne(
    MediaDiscoveryRecord record, {
    required int now,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  }) async {
    final newRow = _mapper.forInsert(
      record,
      nowSeconds: now,
      generationAfter: generationAfter,
      accessScope: accessScope,
    );
    await _db
        .into(_db.mediaItems)
        .insert(
          newRow,
          onConflict: DoUpdate(
            (old) => _mapper.forConflictUpdate(
              old,
              record,
              nowSeconds: now,
              generationAfter: generationAfter,
              accessScope: accessScope,
            ),
          ),
        );
  }

  @override
  Future<MediaItem?> fetchByStableKey(String stableKey) async {
    final query = _db.select(_db.mediaItems)
      ..where((row) => row.stableKey.equals(stableKey));
    return query.getSingleOrNull();
  }

  @override
  Future<List<MediaItem>> fetchByStableKeys(Iterable<String> stableKeys) async {
    final keys = stableKeys.toList(growable: false);
    if (keys.isEmpty) {
      return const [];
    }
    final query = _db.select(_db.mediaItems)
      ..where((row) => row.stableKey.isIn(keys));
    return query.get();
  }

  @override
  Future<int> count() async {
    final query = _db.selectOnly(_db.mediaItems)..addColumns([countAll()]);
    final row = await query.getSingle();
    return row.read(countAll()) ?? 0;
  }

  @override
  Future<MediaIndexStats> stats() async {
    final total = await count();

    final byCategoryRow = _db.selectOnly(_db.mediaItems)
      ..addColumns([_db.mediaItems.category, _db.mediaItems.category.count()])
      ..groupBy([_db.mediaItems.category]);
    final byCategory = <ContentCategory, int>{};
    for (final row in await byCategoryRow.get()) {
      final category = row.read(_db.mediaItems.category)!;
      final count = row.read(_db.mediaItems.category.count()) ?? 0;
      byCategory[ContentCategory.fromWire(category)] = count;
    }

    final volumeRow = _db.selectOnly(_db.mediaItems)
      ..addColumns([_db.mediaItems.volumeName.count(distinct: true)]);
    final volumeCount =
        (await volumeRow.getSingle()).read(
          _db.mediaItems.volumeName.count(distinct: true),
        ) ??
        0;

    return MediaIndexStats(
      total: total,
      byCategory: byCategory,
      volumeCount: volumeCount,
    );
  }

  @override
  Future<bool> deleteByStableKey(String stableKey) async {
    final deleted = await (_db.delete(
      _db.mediaItems,
    )..where((row) => row.stableKey.equals(stableKey))).go();
    return deleted > 0;
  }

  @override
  Future<void> deleteByStableKeys(Iterable<String> stableKeys) async {
    final keys = stableKeys.toList(growable: false);
    for (var start = 0; start < keys.length; start += deleteChunkSize) {
      final end = (start + deleteChunkSize < keys.length)
          ? start + deleteChunkSize
          : keys.length;
      final chunk = keys.sublist(start, end);
      await (_db.delete(
        _db.mediaItems,
      )..where((row) => row.stableKey.isIn(chunk))).go();
    }
  }

  @override
  Future<List<IndexedMediaId>> fetchIndexedPage({
    required ContentCategory category,
    required String volumeName,
    int afterId = 0,
    int limit = 500,
  }) async {
    assert(limit > 0, 'limit must be positive');
    final query = _db.select(_db.mediaItems)
      ..where(
        (row) =>
            row.category.equals(category.name) &
            row.volumeName.equals(volumeName) &
            row.mediaStoreId.isBiggerThanValue(afterId),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.mediaStoreId)])
      ..limit(limit);
    final rows = await query.get();
    return rows
        .map(
          (row) => IndexedMediaId(
            stableKey: row.stableKey,
            mediaStoreId: row.mediaStoreId,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<UpsertBatchDelta> upsertBatchChanged(
    Iterable<MediaDiscoveryRecord> records, {
    int? nowSeconds,
    int? generationAfter,
    DiscoveryAccessScope? accessScope,
  }) async {
    final now = nowSeconds ?? _nowSeconds();
    final snapshot = List<MediaDiscoveryRecord>.of(records);
    if (snapshot.isEmpty) {
      return const UpsertBatchDelta(inserted: 0, updated: 0, unchanged: 0);
    }

    final existingRows = await fetchByStableKeys(
      snapshot.map((record) => record.stableKey),
    );
    final existingByKey = {for (final row in existingRows) row.stableKey: row};

    var inserted = 0;
    var updated = 0;
    var unchanged = 0;
    await _db.transaction(() async {
      for (final record in snapshot) {
        final existing = existingByKey[record.stableKey];
        if (existing == null) {
          await _upsertOne(
            record,
            now: now,
            generationAfter: generationAfter,
            accessScope: accessScope,
          );
          inserted += 1;
        } else if (_mapper.sameContent(existing, record)) {
          unchanged += 1;
        } else {
          await _upsertOne(
            record,
            now: now,
            generationAfter: generationAfter,
            accessScope: accessScope,
          );
          updated += 1;
        }
      }
    });

    return UpsertBatchDelta(
      inserted: inserted,
      updated: updated,
      unchanged: unchanged,
    );
  }

  @override
  Future<SyncCheckpoint?> getSyncCheckpoint(
    ContentCategory category,
    String volumeName,
  ) async {
    final query = _db.select(_db.indexState)
      ..where(
        (row) =>
            row.category.equals(category.name) &
            row.volumeName.equals(volumeName),
      );
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return SyncCheckpoint(
      category: category,
      volumeName: volumeName,
      lastGeneration: row.lastGeneration,
      lastAccessScope: DiscoveryAccessScope.fromWire(row.lastAccessScope),
      lastSyncAt: row.lastSyncAt,
      lastResult: row.lastResult,
    );
  }

  @override
  Future<void> saveSyncCheckpoint(SyncCheckpoint checkpoint) async {
    await _db
        .into(_db.indexState)
        .insertOnConflictUpdate(
          IndexStateCompanion.insert(
            category: checkpoint.category.name,
            volumeName: checkpoint.volumeName,
            lastGeneration: Value<int?>(checkpoint.lastGeneration),
            lastAccessScope: checkpoint.lastAccessScope.name,
            lastSyncAt: checkpoint.lastSyncAt,
            lastResult: checkpoint.lastResult,
          ),
        );
  }

  @override
  Future<void> clearAll() => _db.delete(_db.mediaItems).go().then((_) {});

  static const deleteChunkSize = 500;

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
