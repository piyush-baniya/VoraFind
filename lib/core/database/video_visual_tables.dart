import 'package:drift/drift.dart';

/// Durable lifecycle of one video's visual analysis (schema v7,
/// `docs/video-visual-search.md`).
///
/// One row per video, keyed by the media row's stable identity. A missing row
/// means "not yet analyzed". `completed` rows carry the source revision and
/// model they were produced from — a revision or model change makes them stale.
/// `failed` rows retry after the cooldown; `unsupported` rows are terminal
/// (empty input, corrupt/DRM video, unknown model output).
class VideoVisualStatus extends Table {
  /// Stable identity of the source media row (`media_items.stable_key`).
  TextColumn get stableKey => text()();

  /// `media_items.metadata_revision` at analysis time. A revision bump makes
  /// the analysis stale.
  IntColumn get sourceRevision => integer()();

  /// The vision model that produced the frame rows
  /// (`VisualFrameClassifier.modelId`). A model change invalidates them.
  TextColumn get modelId => text()();

  /// Durable analysis status ([VisualVideoStatus.name]).
  TextColumn get status => text()();

  /// Stable failure code (`VisualErrorCode.name`); null when not failed.
  TextColumn get errorCode => text().nullable()();

  /// Epoch seconds of the first write.
  IntColumn get createdAt => integer()();

  /// Epoch seconds of the most recent write (drives retry cooldowns).
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {stableKey};
}

/// Derived visual concepts per sampled frame (schema v7).
///
/// One row per (video, frame, concept). Never stores frame bytes — only the
/// bounded derived concept + confidence + the frame's timestamp inside the
/// video. Indexed on concept for bounded concept-based retrieval and on
/// stable key for per-video cleanup.
@TableIndex(name: 'idx_vvf_concept_conf', columns: {#concept, #confidence})
@TableIndex(name: 'idx_vvf_stable_key', columns: {#stableKey})
class VideoVisualFrames extends Table {
  /// Stable identity of the source media row (`media_items.stable_key`).
  TextColumn get stableKey => text()();

  /// 0-based frame slot inside the video (0..maxFramesPerVideo-1).
  IntColumn get frameIndex => integer()();

  /// Milliseconds from the start of the video for this frame.
  IntColumn get frameTsMs => integer()();

  /// Curated concept identity (`VisualConceptMap`), the searchable surface.
  TextColumn get concept => text()();

  /// Aggregated label confidence in `[minConceptConfidence, 1]`. The search
  /// ranker maps this to visual rank points.
  RealColumn get confidence => real()();

  @override
  Set<Column<Object>> get primaryKey => {stableKey, frameIndex, concept};
}
