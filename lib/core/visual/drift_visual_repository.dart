import 'package:drift/drift.dart';

import '../database/app_database.dart'
    show AppDatabase, VideoVisualFramesCompanion, VideoVisualStatusCompanion;
import '../database/media_items_table.dart' show MediaItems;
import '../database/video_visual_tables.dart' show VideoVisualStatus;
import '../platform/content_access_models.dart' show ContentCategory;
import '../visual/visual_models.dart';
import '../visual/visual_repository.dart';

/// Drift-backed store over `video_visual_status` and `video_visual_frames`
/// (schema v7).
///
/// Indexing-side retrieval is bounded and resumable: the eligibility WHERE
/// clause (missing/stale/failed-past-cooldown) mirrors the OCR and semantic
/// repositories so a run only touches videos that genuinely need work.
/// Search-side retrieval is **bounded and filter-aware**: the SQL fetch caps
/// the pool and applies media/duration/date filters before ranking so visual
/// results can never cross a filter boundary.
class DriftVisualRepository
    implements VisualIndexRepository, VisualSearchRepository {
  DriftVisualRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // Indexing side
  // ---------------------------------------------------------------------------

  @override
  Future<List<VisualCandidate>> findVisualCandidates({
    required int batchSize,
    required String modelId,
    required int nowEpochSeconds,
    int retryCooldownSeconds = VisualDefaults.retryCooldownSeconds,
  }) async {
    final media = _db.mediaItems;
    final status = _db.videoVisualStatus;
    final cooldownCutoff = nowEpochSeconds - retryCooldownSeconds;

    final query =
        _db.select(media).join([
            leftOuterJoin(status, status.stableKey.equalsExp(media.stableKey)),
          ])
          ..where(media.category.equals(ContentCategory.videos.name))
          ..where(
            _eligibility(
              status,
              media: media,
              modelId: modelId,
              cooldownCutoff: cooldownCutoff,
            ),
          )
          ..orderBy([OrderingTerm.asc(media.stableKey)])
          ..limit(batchSize);

    final rows = await query.get();
    final result = <VisualCandidate>[];
    for (final row in rows) {
      final m = row.readTable(media);
      result.add(
        VisualCandidate(
          stableKey: m.stableKey,
          sourceRevision: m.metadataRevision,
          contentUri: m.contentUri,
          durationMs: m.durationMs,
          displayName: m.displayName,
        ),
      );
    }
    return result;
  }

  static Expression<bool> _eligibility(
    VideoVisualStatus s, {
    required MediaItems media,
    required String modelId,
    required int cooldownCutoff,
  }) {
    final missingRow = s.stableKey.isNull();
    final staleCompleted =
        s.status.equals(VisualVideoStatus.completed.name) &
        s.sourceRevision.isSmallerThan(media.metadataRevision);
    final staleModel =
        s.status.equals(VisualVideoStatus.completed.name) &
        s.modelId.equals(modelId).not();
    final retryFailure =
        s.status.equals(VisualVideoStatus.failed.name) &
        s.updatedAt.isSmallerOrEqualValue(cooldownCutoff);
    return missingRow | staleCompleted | staleModel | retryFailure;
  }

  @override
  Future<void> saveAnalysis({
    required String stableKey,
    required int sourceRevision,
    required String modelId,
    required List<AnalyzedVisualFrame> frames,
    required int nowEpochSeconds,
  }) async {
    await _db.transaction(() async {
      await _db
          .into(_db.videoVisualStatus)
          .insert(
            VideoVisualStatusCompanion.insert(
              stableKey: stableKey,
              sourceRevision: sourceRevision,
              modelId: modelId,
              status: VisualVideoStatus.completed.name,
              createdAt: nowEpochSeconds,
              updatedAt: nowEpochSeconds,
            ),
            onConflict: DoUpdate(
              (_) => VideoVisualStatusCompanion(
                sourceRevision: Value(sourceRevision),
                modelId: Value(modelId),
                status: Value(VisualVideoStatus.completed.name),
                errorCode: Value(null),
                updatedAt: Value(nowEpochSeconds),
              ),
            ),
          );
      await (_db.delete(
        _db.videoVisualFrames,
      )..where((f) => f.stableKey.equals(stableKey))).go();
      if (frames.isNotEmpty) {
        final rows = <VideoVisualFramesCompanion>[];
        for (final frame in frames) {
          for (final concept in frame.concepts) {
            rows.add(
              VideoVisualFramesCompanion.insert(
                stableKey: stableKey,
                frameIndex: frame.frameIndex,
                frameTsMs: frame.frameTsMs,
                concept: concept.concept,
                confidence: concept.confidenceLabel,
              ),
            );
          }
        }
        await _db.batch((batch) {
          batch.insertAll(_db.videoVisualFrames, rows);
        });
      }
    });
  }

  @override
  Future<void> saveFailure({
    required String stableKey,
    required int sourceRevision,
    required String modelId,
    required String errorCode,
    required int nowEpochSeconds,
    required bool permanent,
  }) async {
    final status = permanent
        ? VisualVideoStatus.unsupported.name
        : VisualVideoStatus.failed.name;
    await _db
        .into(_db.videoVisualStatus)
        .insert(
          VideoVisualStatusCompanion.insert(
            stableKey: stableKey,
            sourceRevision: sourceRevision,
            modelId: modelId,
            status: status,
            errorCode: Value(errorCode),
            createdAt: nowEpochSeconds,
            updatedAt: nowEpochSeconds,
          ),
          onConflict: DoUpdate(
            (_) => VideoVisualStatusCompanion(
              sourceRevision: Value(sourceRevision),
              modelId: Value(modelId),
              status: Value(status),
              errorCode: Value(errorCode),
              updatedAt: Value(nowEpochSeconds),
            ),
          ),
        );
  }

  @override
  Future<VisualStats> stats() async {
    var completed = 0;
    var failed = 0;
    var unsupported = 0;
    final totalQuery = _db.selectOnly(_db.videoVisualStatus)
      ..addColumns([countAll()]);
    final total = (await totalQuery.getSingle()).read(countAll()) ?? 0;
    final byStatus = _db.selectOnly(_db.videoVisualStatus)
      ..addColumns([_db.videoVisualStatus.status, countAll()])
      ..groupBy([_db.videoVisualStatus.status]);
    for (final row in await byStatus.get()) {
      final count = row.read(countAll()) ?? 0;
      switch (row.read(_db.videoVisualStatus.status)) {
        case 'completed':
          completed = count;
        case 'failed':
          failed = count;
        case 'unsupported':
          unsupported = count;
        case _:
          break;
      }
    }
    final framesQuery = _db.selectOnly(_db.videoVisualFrames)
      ..addColumns([countAll()]);
    final frames = (await framesQuery.getSingle()).read(countAll()) ?? 0;
    return VisualStats(
      total: total,
      completed: completed,
      failed: failed,
      unsupported: unsupported,
      videoFrames: frames,
    );
  }

  @override
  Future<VisualVideoStatus?> getStatus(String stableKey) async {
    final row = await (_db.select(
      _db.videoVisualStatus,
    )..where((s) => s.stableKey.equals(stableKey))).getSingleOrNull();
    if (row == null) return null;
    return VisualVideoStatus.values.asNameMap()[row.status] ??
        VisualVideoStatus.failed;
  }

  @override
  Future<void> clear() async {
    await _db.transaction(() async {
      await _db.delete(_db.videoVisualFrames).go();
      await _db.delete(_db.videoVisualStatus).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Search side
  // ---------------------------------------------------------------------------

  @override
  Future<List<VisualRetrievalMatch>> retrieveVisualCandidates({
    required List<String> concepts,
    required int maxResults,
    List<String>? mediaCategories,
    int? dateFrom,
    int? dateTo,
    int? minDurationMs,
    int? maxDurationMs,
    double minConfidence = VisualDefaults.minConceptConfidence,
  }) async {
    if (concepts.isEmpty) return const [];
    final limit = maxResults < 1
        ? 1
        : _mathMin(
            maxResults * VisualDefaults.candidatePoolMultiple,
            VisualDefaults.maxCandidatePool,
          );

    final frame = _db.videoVisualFrames;
    final status = _db.videoVisualStatus;
    final media = _db.mediaItems;

    final query =
        _db.select(frame).join([
            innerJoin(
              status,
              status.stableKey.equalsExp(frame.stableKey) &
                  status.status.equals(VisualVideoStatus.completed.name),
            ),
            innerJoin(media, media.stableKey.equalsExp(frame.stableKey)),
          ])
          ..where(
            frame.concept.isIn(concepts) &
                frame.confidence.isBiggerOrEqualValue(minConfidence) &
                _searchFilters(
                  media,
                  mediaCategories: mediaCategories,
                  dateFrom: dateFrom,
                  dateTo: dateTo,
                  minDurationMs: minDurationMs,
                  maxDurationMs: maxDurationMs,
                ),
          )
          ..orderBy([
            OrderingTerm.desc(frame.confidence),
            OrderingTerm.asc(frame.stableKey),
          ])
          ..limit(limit);

    final rows = await query.get();

    // Pick the single best (highest-confidence) frame per video-concept pair,
    // then cap the pool deterministically (confidence desc → stableKey asc).
    // Visual frames only exist for videos, so this surface is inherently video.
    final best = <String, VisualRetrievalMatch>{};
    for (final row in rows) {
      final f = row.readTable(frame);
      final key = '${f.stableKey}\u0000${f.concept}';
      final existing = best[key];
      if (existing == null || f.confidence > existing.confidence) {
        best[key] = VisualRetrievalMatch(
          stableKey: f.stableKey,
          concept: f.concept,
          confidence: f.confidence,
          frameTsMs: f.frameTsMs,
        );
      }
    }
    final matches = best.values.toList(growable: false)
      ..sort((a, b) {
        final byConfidence = b.confidence.compareTo(a.confidence);
        if (byConfidence != 0) return byConfidence;
        return a.stableKey.compareTo(b.stableKey);
      });
    return matches.take(maxResults).toList(growable: false);
  }

  Expression<bool> _searchFilters(
    MediaItems m, {
    List<String>? mediaCategories,
    int? dateFrom,
    int? dateTo,
    int? minDurationMs,
    int? maxDurationMs,
  }) {
    Expression<bool> where =
        m.category.equals(ContentCategory.videos.name) &
        m.durationMs.isNotNull();
    if (mediaCategories != null && mediaCategories.isNotEmpty) {
      where = where & m.category.isIn(mediaCategories);
    }
    if (dateFrom != null) {
      where = where & m.dateModified.isBiggerOrEqualValue(dateFrom);
    }
    if (dateTo != null) {
      where = where & m.dateModified.isSmallerOrEqualValue(dateTo);
    }
    if (minDurationMs != null) {
      where = where & m.durationMs.isBiggerOrEqualValue(minDurationMs);
    }
    if (maxDurationMs != null) {
      where = where & m.durationMs.isSmallerOrEqualValue(maxDurationMs);
    }
    return where;
  }

  static int _mathMin(int a, int b) => a < b ? a : b;
}
