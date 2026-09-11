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
  Future<void> clearAll() => _db.delete(_db.mediaItems).go().then((_) {});

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
