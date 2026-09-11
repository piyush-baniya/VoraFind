import 'package:drift/drift.dart';

import '../ocr/ocr_models.dart' show OcrStatus;
import '../platform/content_access_models.dart' show ContentCategory;
import '../platform/media_discovery_models.dart'
    show DiscoveryAccessScope, MediaDiscoveryRecord;
import '../search/search_normalizer.dart';
import '../search/search_query.dart';
import 'app_database.dart';
import 'media_item_mapper.dart';
import 'media_items_table.dart';
import 'ocr_content_table.dart';

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

/// Defaults for the OCR enrichment pipeline (docs `ocr.md`).
abstract final class OcrDefaults {
  /// MIME types VoraFind will run OCR over. Everything else (documents, video
  /// frames, audio) stays out of scope for this prompt (AGENTS.md §27).
  static const List<String> supportedMimeTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/bmp',
    'image/gif',
  ];

  /// How long a transient failure cools down before the row is retried.
  static const int retryCooldownSeconds = 60 * 60;

  /// Default number of rows drained per coordinator batch.
  static const int batchSize = 25;
}

/// Aggregated OCR state for progress/status surfaces.
class OcrStats {
  const OcrStats({
    required this.eligible,
    required this.completed,
    required this.failed,
    required this.unsupported,
  });

  /// Image rows in the OCR-supported mime set (the population `completed`,
  /// `failed`, `unsupported` partition; `eligible - pending` rows have no
  /// `ocr_content` row yet).
  final int eligible;
  final int completed;
  final int failed;
  final int unsupported;
}

/// Durable OCR state of one media row (mirror of the `ocr_content` columns
/// the coordinator and status surfaces need).
class OcrIndexedRow {
  const OcrIndexedRow({
    required this.stableKey,
    required this.status,
    required this.sourceRevision,
    required this.updatedAt,
    this.errorCode,
  });

  final String stableKey;
  final OcrStatus status;
  final int sourceRevision;
  final int updatedAt;
  final String? errorCode;
}

/// One OCR-search candidate: the media row plus the recognition text it was
/// retrieved through (already current — stale revisions are filtered in SQL).
class OcrSearchMatch {
  const OcrSearchMatch({required this.item, required this.normalizedText});

  final MediaItem item;
  final String normalizedText;
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

  /// Retrieves the bounded candidate pool for a prepared search.
  ///
  /// SQLite performs as much filtering as practical (category, screenshot,
  /// date/size/duration/path filters, keyword containment on the normalized
  /// `searchable_text` column), then orders the pool by keyword coverage,
  /// recency, and stable key before capping at
  /// `SearchLimits.candidatePoolMultiple × limit`. The caller ranks this
  /// bounded pool in Dart — never the whole index. Understands
  /// `NormalizedSearchQuery` directly so the UI cannot bypass the service.
  Future<List<MediaItem>> searchCandidates(NormalizedSearchQuery query);

  /// Same bounded retrieval as [searchCandidates], but keyword containment
  /// runs on OCR text (`ocr_content.normalized_text`) instead of metadata.
  ///
  /// Only current (`status == completed`, `source_revision ==
  /// media.metadata_revision`) rows are returned, so a row whose image changed
  /// since it was last recognized cannot surface stale text.
  Future<List<OcrSearchMatch>> searchOcrCandidates(NormalizedSearchQuery query);

  /// Next [batchSize] images awaiting OCR, screenshots first then stable key,
  /// respecting the retry policy in `docs/ocr.md`:
  ///
  /// * never-processed images **only when last seen under full access** (a
  ///   user who granted only a photo-picker selection has not authorized
  ///   reading every indexed body — AGENTS.md §9);
  /// * [OcrStatus.failed] rows whose cooldown expired (`nowEpochSeconds -
  ///   retryCooldownSeconds ≥ updated_at`);
  /// * [OcrStatus.completed] rows whose `source_revision < metadata_revision`
  ///   (the image's metadata changed, so the text is stale).
  ///
  /// [OcrStatus.unsupported] rows are permanent and never returned.
  Future<List<MediaItem>> findOcrCandidates({
    required int batchSize,
    required int nowEpochSeconds,
    int retryCooldownSeconds = OcrDefaults.retryCooldownSeconds,
  });

  /// Idempotently persists one recognition outcome. On a conflict the row is
  /// updated in place; `created_at` is preserved, `updated_at` advances and a
  /// null [text] records a failed/unsupported outcome (`errorCode` carries the
  /// stable `OcrErrorCode.name`).
  Future<void> saveOcrResult({
    required String stableKey,
    required String? text,
    required OcrStatus status,
    required int sourceRevision,
    required int nowEpochSeconds,
    String? errorCode,
  });

  /// Durable OCR state of [stableKey], or null when never processed.
  Future<OcrIndexedRow?> getOcrStatus(String stableKey);

  /// Aggregated OCR progress for the UI.
  Future<OcrStats> ocrStats();

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
    await (_db.delete(
      _db.ocrContent,
    )..where((row) => row.mediaStableKey.equals(stableKey))).go();
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
        _db.ocrContent,
      )..where((row) => row.mediaStableKey.isIn(chunk))).go();
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
  Future<List<MediaItem>> searchCandidates(NormalizedSearchQuery query) async {
    final t = _db.mediaItems;
    final tokens = query.tokens;
    final pool = _candidatePool(query);

    final base = _db.select(t)
      ..where(
        (row) =>
            _searchWhere(row, query) &
            (tokens.isEmpty ? const Constant(true) : _keywordPredicate(tokens)),
      )
      ..limit(pool);

    if (tokens.isNotEmpty) {
      base.orderBy([
        (row) => OrderingTerm.desc(_coverageExpression(tokens)),
        (row) => OrderingTerm.desc(row.dateModified),
        (row) => OrderingTerm.asc(row.stableKey),
      ]);
    } else {
      base.orderBy([
        (row) => OrderingTerm.desc(row.dateModified),
        (row) => OrderingTerm.asc(row.stableKey),
      ]);
    }
    return base.get();
  }

  @override
  Future<List<OcrSearchMatch>> searchOcrCandidates(
    NormalizedSearchQuery query,
  ) async {
    final t = _db.mediaItems;
    final o = _db.ocrContent;
    final tokens = query.tokens;
    final pool = _candidatePool(query);

    final statement = _db.select(t).join([
      innerJoin(o, o.mediaStableKey.equalsExp(t.stableKey)),
    ]);

    statement
      ..where(
        _searchWhere(t, query) &
            o.status.equals(OcrStatus.completed.name) &
            // Never surface text recognized from a different image revision.
            o.sourceRevision.equalsExp(t.metadataRevision) &
            (tokens.isEmpty
                ? const Constant(true)
                : _ocrKeywordPredicate(o, tokens)),
      )
      ..orderBy([
        if (tokens.isNotEmpty)
          OrderingTerm.desc(_ocrCoverageExpression(o, tokens)),
        OrderingTerm.desc(t.dateModified),
        OrderingTerm.asc(t.stableKey),
      ])
      ..limit(pool);

    final rows = await statement.get();
    return rows
        .map(
          (row) => OcrSearchMatch(
            item: row.readTable(t),
            normalizedText: row.readTable(o).normalizedText ?? '',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MediaItem>> findOcrCandidates({
    required int batchSize,
    required int nowEpochSeconds,
    int retryCooldownSeconds = OcrDefaults.retryCooldownSeconds,
  }) async {
    assert(batchSize > 0, 'batchSize must be positive');
    final t = _db.mediaItems;
    final o = _db.ocrContent;
    final cooldownCutoff = nowEpochSeconds - retryCooldownSeconds;

    final statement = _db.select(t).join([
      leftOuterJoin(o, o.mediaStableKey.equalsExp(t.stableKey)),
    ]);
    statement
      ..where(
        t.category.equals('images') &
            t.mimeType.isIn(OcrDefaults.supportedMimeTypes) &
            _ocrEligibility(t, o, cooldownCutoff),
      )
      ..orderBy([
        OrderingTerm.desc(t.isScreenshot),
        OrderingTerm.asc(t.stableKey),
      ])
      ..limit(batchSize);

    final rows = await statement.get();
    return rows.map((row) => row.readTable(t)).toList(growable: false);
  }

  /// True when a row still needs (or may be retried for) OCR. See the
  /// interface contract for the privacy rationale of the full-scope gate.
  Expression<bool> _ocrEligibility(
    MediaItems t,
    OcrContent o,
    int cooldownCutoff,
  ) {
    final neverProcessed =
        o.status.isNull() & t.lastSeenAccessScope.equals('full');
    final retryExpiredFailure =
        o.status.equals(OcrStatus.failed.name) &
        o.updatedAt.isSmallerOrEqualValue(cooldownCutoff);
    final staleCompletion =
        o.status.equals(OcrStatus.completed.name) &
        o.sourceRevision.isSmallerThan(t.metadataRevision);
    return neverProcessed | retryExpiredFailure | staleCompletion;
  }

  @override
  Future<void> saveOcrResult({
    required String stableKey,
    required String? text,
    required OcrStatus status,
    required int sourceRevision,
    required int nowEpochSeconds,
    String? errorCode,
  }) async {
    final normalized = text == null ? null : SearchNormalizer.canonical(text);
    await _db
        .into(_db.ocrContent)
        .insert(
          OcrContentCompanion.insert(
            mediaStableKey: stableKey,
            rawText: Value<String?>(text),
            normalizedText: Value<String?>(normalized),
            status: status,
            sourceRevision: sourceRevision,
            createdAt: nowEpochSeconds,
            updatedAt: nowEpochSeconds,
            errorCode: Value<String?>(errorCode),
          ),
          onConflict: DoUpdate(
            (_) => OcrContentCompanion(
              rawText: Value<String?>(text),
              normalizedText: Value<String?>(normalized),
              status: Value(status),
              sourceRevision: Value(sourceRevision),
              updatedAt: Value(nowEpochSeconds),
              errorCode: Value<String?>(errorCode),
            ),
          ),
        );
  }

  @override
  Future<OcrIndexedRow?> getOcrStatus(String stableKey) async {
    final row = await (_db.select(
      _db.ocrContent,
    )..where((r) => r.mediaStableKey.equals(stableKey))).getSingleOrNull();
    if (row == null) return null;
    return OcrIndexedRow(
      stableKey: row.mediaStableKey,
      status: row.status,
      sourceRevision: row.sourceRevision,
      updatedAt: row.updatedAt,
      errorCode: row.errorCode,
    );
  }

  @override
  Future<OcrStats> ocrStats() async {
    final eligibleQuery = _db.selectOnly(_db.mediaItems)
      ..addColumns([countAll()])
      ..where(
        _db.mediaItems.category.equals('images') &
            _db.mediaItems.mimeType.isIn(OcrDefaults.supportedMimeTypes),
      );
    final eligible = (await eligibleQuery.getSingle()).read(countAll()) ?? 0;

    var completed = 0;
    var failed = 0;
    var unsupported = 0;
    final byStatus = _db.selectOnly(_db.ocrContent)
      ..addColumns([_db.ocrContent.status, countAll()])
      ..groupBy([_db.ocrContent.status]);
    for (final row in await byStatus.get()) {
      final count = row.read(countAll()) ?? 0;
      switch (row.readWithConverter(_db.ocrContent.status)) {
        case OcrStatus.completed:
          completed = count;
        case OcrStatus.failed:
          failed = count;
        case OcrStatus.unsupported:
          unsupported = count;
        case null:
          break;
      }
    }
    return OcrStats(
      eligible: eligible,
      completed: completed,
      failed: failed,
      unsupported: unsupported,
    );
  }

  /// `OCRConten.normalized_text LIKE '%token%'` OR-ed together, wildcard-safe
  /// for the same reason as [_keywordPredicate].
  Expression<bool> _ocrKeywordPredicate(OcrContent o, List<String> tokens) {
    return tokens
        .map((token) => o.normalizedText.contains(token))
        .reduce((a, b) => a | b);
  }

  /// Coverage of OCR tokens, ordering the pool by how many terms the *body
  /// text* contains before the Dart ranker re-ranks it.
  Expression<int> _ocrCoverageExpression(OcrContent o, List<String> tokens) {
    final parts = tokens
        .map((token) => "(instr(ocr_content.normalized_text, '$token') > 0)")
        .join(' + ');
    if (parts.isEmpty) return CustomExpression<int>('(0)');
    return CustomExpression<int>('($parts)');
  }

  /// Builds the structured filter conjunction for [query]. Never includes the
  /// keyword predicate — the caller adds that so keyword/config stays clear.
  Expression<bool> _searchWhere(MediaItems row, NormalizedSearchQuery query) {
    Expression<bool> where = const Constant(true);

    if (query.categories.isNotEmpty) {
      final names = query.categories.map((category) => category.name);
      where = where & row.category.isIn(names);
    }
    final screenshot = query.isScreenshot;
    if (screenshot != null) {
      where = where & row.isScreenshot.equals(screenshot);
    }
    final dateFrom = query.dateFrom;
    if (dateFrom != null) {
      where = where & row.dateModified.isBiggerOrEqualValue(dateFrom);
    }
    final dateTo = query.dateTo;
    if (dateTo != null) {
      where = where & row.dateModified.isSmallerOrEqualValue(dateTo);
    }
    final minSize = query.minSizeBytes;
    if (minSize != null) {
      where = where & row.sizeBytes.isBiggerOrEqualValue(minSize);
    }
    final maxSize = query.maxSizeBytes;
    if (maxSize != null) {
      where = where & row.sizeBytes.isSmallerOrEqualValue(maxSize);
    }
    final pathPrefix = query.pathPrefix;
    if (pathPrefix != null && pathPrefix.isNotEmpty) {
      where = where & _pathPrefixPredicate(row.relativePath, pathPrefix);
    }
    final minDuration = query.minDurationMs;
    if (minDuration != null) {
      where = where & row.durationMs.isBiggerOrEqualValue(minDuration);
    }
    final maxDuration = query.maxDurationMs;
    if (maxDuration != null) {
      where = where & row.durationMs.isSmallerOrEqualValue(maxDuration);
    }
    return where;
  }

  /// `searchable_text LIKE '%token%'` per token, OR-ed together.
  ///
  /// Safe without escaping: both the stored value and the tokens are
  /// normalized to `[a-z0-9 ]` only (see `SearchNormalizer`), so `%`/`_` can
  /// never act as wildcards on either side of the pattern.
  Expression<bool> _keywordPredicate(List<String> tokens) {
    return tokens
        .map((token) => _db.mediaItems.searchableText.contains(token))
        .reduce((a, b) => a | b);
  }

  /// Prefix match on `relative_path` (`'prefix%'`) with LIKE wildcards in the
  /// user prefix escaped, so `_`/`%` in a folder name are literal. The
  /// `idx_media_relative_path` index makes pure-prefix filters cheap.
  Expression<bool> _pathPrefixPredicate(
    Expression<String> column,
    String prefix,
  ) {
    final escaped = prefix
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return column.like('$escaped%', escapeChar: r'\');
  }

  /// `(instr(searchable_text,'t1')>0)+(instr(searchable_text,'t2')>0)+…` used
  /// to order the pool by how many distinct tokens a row contains — rows
  /// matching more tokens reach the top of the bounded pool before Dart
  /// re-ranks them.
  ///
  /// [tokens] are guaranteed alphanumeric by `SearchNormalizer`, so embedding
  /// them literally is injection-safe (no quotes or wildcards possible).
  Expression<int> _coverageExpression(List<String> tokens) {
    final parts = tokens
        .map((token) => "(instr(searchable_text, '$token') > 0)")
        .join(' + ');
    return CustomExpression<int>('($parts)');
  }

  /// Candidate pool: a bounded multiple of the result limit so the Dart ranker
  /// has slack, capped absolutely. Filter-only searches need no slack — recency
  /// ordering is final — so they use exactly the limit.
  static int _candidatePool(NormalizedSearchQuery query) {
    if (!query.hasKeyword) return query.limit;
    final multiple = query.limit * SearchLimits.candidatePoolMultiple;
    return multiple > SearchLimits.maxCandidatePool
        ? SearchLimits.maxCandidatePool
        : multiple;
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
  Future<void> clearAll() async {
    await _db.delete(_db.ocrContent).go();
    await _db.delete(_db.mediaItems).go();
  }

  static const deleteChunkSize = 500;

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
