import 'package:drift/drift.dart';

import '../database/app_database.dart'
    show AppDatabase, SemanticEmbedding, SemanticEmbeddingsCompanion;
import '../database/documents_table.dart';
import '../database/media_items_table.dart';
import '../ocr/ocr_models.dart' show OcrStatus;
import 'semantic_embeddings_table.dart';
import 'semantic_models.dart';
import 'semantic_repository.dart';
import 'vector_codec.dart';
import 'vector_math.dart';

/// Drift-backed store over `semantic_embeddings` (schema v6).
///
/// Retrieval is deliberately **bounded brute-force**: the SQL fetch caps the
/// pool and filters to completed, model-current vectors; only that pool's
/// vectors are decoded and scored in Dart. A future native/vector ANN index
/// replaces this class behind the same interfaces without the search layer
/// changing (docs `semantic-search.md` Â§Vector index).
class DriftSemanticRepository
    implements SemanticIndexRepository, SemanticSearchRepository {
  DriftSemanticRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // Indexing side
  // ---------------------------------------------------------------------------

  @override
  Future<List<SemanticCandidate>> findEmbeddingCandidates({
    required int batchSize,
    required String modelId,
    required int dimensions,
    required int nowEpochSeconds,
    int retryCooldownSeconds = SemanticDefaults.retryCooldownSeconds,
  }) async {
    final cooldownCutoff = nowEpochSeconds - retryCooldownSeconds;
    final candidates = <SemanticCandidate>[
      ...await _mediaCandidates(
        modelId: modelId,
        cooldownCutoff: cooldownCutoff,
      ),
      ...await _documentCandidates(
        modelId: modelId,
        cooldownCutoff: cooldownCutoff,
        batchSize: batchSize,
      ),
    ];
    return candidates.length > batchSize
        ? candidates.sublist(0, batchSize)
        : candidates;
  }

  Future<List<SemanticCandidate>> _mediaCandidates({
    required String modelId,
    required int cooldownCutoff,
  }) async {
    final media = _db.mediaItems;
    final ocr = _db.ocrContent.createAlias('ocr');
    final sem = _db.semanticEmbeddings.createAlias('sem');

    final query =
        _db.select(media).join([
            leftOuterJoin(ocr, ocr.mediaStableKey.equalsExp(media.stableKey)),
            leftOuterJoin(
              sem,
              sem.stableKey.equalsExp(media.stableKey) &
                  sem.contentType.equals(SemanticContentType.media.name),
            ),
          ])
          ..where(media.category.equals('images'))
          ..where(
            _mediaEligibility(
              media,
              sem,
              modelId: modelId,
              cooldownCutoff: cooldownCutoff,
            ),
          )
          ..orderBy([OrderingTerm.asc(media.stableKey)])
          ..limit(25);

    final rows = await query.get();
    final result = <SemanticCandidate>[];
    for (final row in rows) {
      final m = row.readTable(media);
      final o = row.readTableOrNull(ocr);
      result.add(
        SemanticCandidate(
          stableKey: m.stableKey,
          contentType: SemanticContentType.media,
          sourceRevision: m.metadataRevision,
          displayName: m.displayName,
          relativePath: m.relativePath,
          text: o?.status == OcrStatus.completed ? o?.normalizedText : null,
          isScreenshot: m.isScreenshot,
        ),
      );
    }
    return result;
  }

  Expression<bool> _mediaEligibility(
    MediaItems m,
    SemanticEmbeddings s, {
    required String modelId,
    required int cooldownCutoff,
  }) {
    final missingRow = s.stableKey.isNull();
    final staleCompleted =
        s.status.equals(SemanticEmbeddingStatus.completed.name) &
        s.sourceRevision.isSmallerThan(m.metadataRevision);
    final staleModel =
        s.status.equals(SemanticEmbeddingStatus.completed.name) &
        s.modelId.equals(modelId).not();
    final retryFailure =
        s.status.equals(SemanticEmbeddingStatus.failed.name) &
        s.updatedAt.isSmallerOrEqualValue(cooldownCutoff);
    return missingRow | staleCompleted | staleModel | retryFailure;
  }

  Future<List<SemanticCandidate>> _documentCandidates({
    required String modelId,
    required int cooldownCutoff,
    required int batchSize,
  }) async {
    if (batchSize <= 0) return const [];
    final doc = _db.documents;
    final content = _db.documentContent.createAlias('doc_content');
    final sem = _db.semanticEmbeddings.createAlias('dsem');

    final query =
        _db.select(doc).join([
            leftOuterJoin(
              content,
              content.documentStableKey.equalsExp(doc.stableKey),
            ),
            leftOuterJoin(
              sem,
              sem.stableKey.equalsExp(doc.stableKey) &
                  sem.contentType.equals(SemanticContentType.document.name),
            ),
          ])
          ..where(
            _documentEligibility(
              doc,
              sem,
              modelId: modelId,
              cooldownCutoff: cooldownCutoff,
            ),
          )
          ..orderBy([OrderingTerm.asc(doc.stableKey)])
          ..limit(batchSize);

    final rows = await query.get();
    final result = <SemanticCandidate>[];
    for (final row in rows) {
      final d = row.readTable(doc);
      final c = row.readTableOrNull(content);
      result.add(
        SemanticCandidate(
          stableKey: d.stableKey,
          contentType: SemanticContentType.document,
          sourceRevision: d.sourceRevision,
          displayName: d.displayName,
          relativePath: d.relativePath,
          text: c?.normalizedText,
          isScreenshot: null,
        ),
      );
    }
    return result;
  }

  Expression<bool> _documentEligibility(
    Documents d,
    SemanticEmbeddings s, {
    required String modelId,
    required int cooldownCutoff,
  }) {
    final missingRow = s.stableKey.isNull();
    final staleCompleted =
        s.status.equals(SemanticEmbeddingStatus.completed.name) &
        s.sourceRevision.isSmallerThan(d.sourceRevision);
    final staleModel =
        s.status.equals(SemanticEmbeddingStatus.completed.name) &
        s.modelId.equals(modelId).not();
    final retryFailure =
        s.status.equals(SemanticEmbeddingStatus.failed.name) &
        s.updatedAt.isSmallerOrEqualValue(cooldownCutoff);
    return missingRow | staleCompleted | staleModel | retryFailure;
  }

  @override
  Future<void> saveEmbedding({
    required String stableKey,
    required SemanticContentType contentType,
    required int sourceRevision,
    required String modelId,
    required List<double> vector,
    required int nowEpochSeconds,
  }) async {
    await _db
        .into(_db.semanticEmbeddings)
        .insert(
          SemanticEmbeddingsCompanion.insert(
            stableKey: stableKey,
            contentType: contentType,
            sourceRevision: sourceRevision,
            modelId: modelId,
            dimensions: vector.length,
            embeddingData: Value(VectorCodec.encode(vector)),
            quantization: Value(SemanticDefaults.quantizationF32),
            status: SemanticEmbeddingStatus.completed.name,
            createdAt: nowEpochSeconds,
            updatedAt: nowEpochSeconds,
          ),
          onConflict: DoUpdate(
            (_) => SemanticEmbeddingsCompanion(
              sourceRevision: Value(sourceRevision),
              modelId: Value(modelId),
              dimensions: Value(vector.length),
              embeddingData: Value(VectorCodec.encode(vector)),
              quantization: Value(SemanticDefaults.quantizationF32),
              status: Value(SemanticEmbeddingStatus.completed.name),
              updatedAt: Value(nowEpochSeconds),
            ),
          ),
        );
  }

  @override
  Future<void> saveFailure({
    required String stableKey,
    required SemanticContentType contentType,
    required int sourceRevision,
    required String modelId,
    required String errorCode,
    required int nowEpochSeconds,
    required bool permanent,
  }) async {
    final status = permanent
        ? SemanticEmbeddingStatus.unsupported.name
        : SemanticEmbeddingStatus.failed.name;
    await _db
        .into(_db.semanticEmbeddings)
        .insert(
          SemanticEmbeddingsCompanion.insert(
            stableKey: stableKey,
            contentType: contentType,
            sourceRevision: sourceRevision,
            modelId: modelId,
            dimensions: 0,
            status: status,
            errorCode: Value(errorCode),
            createdAt: nowEpochSeconds,
            updatedAt: nowEpochSeconds,
          ),
          onConflict: DoUpdate(
            (_) => SemanticEmbeddingsCompanion(
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
  Future<SemanticStats> stats() async {
    var completed = 0;
    var failed = 0;
    var unsupported = 0;
    final totalQuery = _db.selectOnly(_db.semanticEmbeddings)
      ..addColumns([countAll()]);
    final total = (await totalQuery.getSingle()).read(countAll()) ?? 0;
    final byStatus = _db.selectOnly(_db.semanticEmbeddings)
      ..addColumns([_db.semanticEmbeddings.status, countAll()])
      ..groupBy([_db.semanticEmbeddings.status]);
    for (final row in await byStatus.get()) {
      final count = row.read(countAll()) ?? 0;
      switch (row.read(_db.semanticEmbeddings.status)) {
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
    return SemanticStats(
      total: total,
      completed: completed,
      failed: failed,
      unsupported: unsupported,
    );
  }

  @override
  Future<SemanticEmbeddingStatus?> getStatus(
    String stableKey,
    SemanticContentType contentType,
  ) async {
    final row =
        await (_db.select(_db.semanticEmbeddings)..where(
              (s) =>
                  s.stableKey.equals(stableKey) &
                  s.contentType.equals(contentType.name),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return SemanticEmbeddingStatus.values.asNameMap()[row.status] ??
        SemanticEmbeddingStatus.failed;
  }

  @override
  Future<void> clear() async {
    await _db.delete(_db.semanticEmbeddings).go();
  }
  // ---------------------------------------------------------------------------
  // Search side (bounded, filter-aware, brute-force top-K)
  // ---------------------------------------------------------------------------

  @override
  Future<List<SemanticMatch>> retrieveSemanticCandidates({
    required List<double> queryVector,
    required String modelId,
    required int dimensions,
    required int maxResults,
    double minSimilarity = SemanticDefaults.minSimilarity,
    required bool includeMedia,
    required bool includeDocuments,
    Set<SemanticContentType>? contentTypes,
    List<String>? mediaCategories,
    bool? isScreenshot,
    List<String>? documentMimeTypes,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  }) async {
    if (queryVector.length != dimensions) return const [];
    if (queryVector.any((v) => v.isNaN || v.isInfinite)) return const [];
    if (!includeMedia && !includeDocuments) return const [];

    final limit = maxResults < 1 ? 1 : maxResults;
    final allowed = contentTypes;
    final matches = <SemanticMatch>[];
    if (includeMedia &&
        (allowed == null || allowed.contains(SemanticContentType.media))) {
      matches.addAll(
        await _retrieveMedia(
          queryVector: queryVector,
          modelId: modelId,
          dimensions: dimensions,
          limit: limit,
          minSimilarity: minSimilarity,
          mediaCategories: mediaCategories,
          isScreenshot: isScreenshot,
          dateFrom: dateFrom,
          dateTo: dateTo,
          pathPrefix: pathPrefix,
        ),
      );
    }
    if (includeDocuments &&
        (allowed == null || allowed.contains(SemanticContentType.document))) {
      matches.addAll(
        await _retrieveDocuments(
          queryVector: queryVector,
          modelId: modelId,
          dimensions: dimensions,
          limit: limit,
          minSimilarity: minSimilarity,
          documentMimeTypes: documentMimeTypes,
          dateFrom: dateFrom,
          dateTo: dateTo,
          pathPrefix: pathPrefix,
        ),
      );
    }
    matches.sort((a, b) {
      final bySim = b.similarity.compareTo(a.similarity);
      if (bySim != 0) return bySim;
      return a.stableKey.compareTo(b.stableKey);
    });
    return matches.take(limit).toList(growable: false);
  }

  Future<List<SemanticMatch>> _retrieveMedia({
    required List<double> queryVector,
    required String modelId,
    required int dimensions,
    required int limit,
    required double minSimilarity,
    List<String>? mediaCategories,
    bool? isScreenshot,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  }) async {
    final semantic = _db.semanticEmbeddings;
    final media = _db.mediaItems;

    final query =
        _db.select(semantic).join([
            innerJoin(media, media.stableKey.equalsExp(semantic.stableKey)),
          ])
          ..where(
            semantic.status.equals(SemanticEmbeddingStatus.completed.name) &
                semantic.modelId.equals(modelId) &
                semantic.dimensions.equals(dimensions) &
                semantic.contentType.equals(SemanticContentType.media.name) &
                _mediaSearchFilters(
                  media,
                  mediaCategories: mediaCategories,
                  isScreenshot: isScreenshot,
                  dateFrom: dateFrom,
                  dateTo: dateTo,
                  pathPrefix: pathPrefix,
                ),
          )
          ..limit(limit * SemanticDefaults.candidatePoolMultiple);

    final rows = await query.get();
    return _scoreAndPick(
      rows.map((row) => row.readTable(semantic)).toList(growable: false),
      queryVector,
      minSimilarity,
      limit,
    );
  }

  Future<List<SemanticMatch>> _retrieveDocuments({
    required List<double> queryVector,
    required String modelId,
    required int dimensions,
    required int limit,
    required double minSimilarity,
    List<String>? documentMimeTypes,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  }) async {
    final semantic = _db.semanticEmbeddings;
    final documents = _db.documents;

    final query =
        _db.select(semantic).join([
            innerJoin(
              documents,
              documents.stableKey.equalsExp(semantic.stableKey),
            ),
          ])
          ..where(
            semantic.status.equals(SemanticEmbeddingStatus.completed.name) &
                semantic.modelId.equals(modelId) &
                semantic.dimensions.equals(dimensions) &
                semantic.contentType.equals(SemanticContentType.document.name) &
                _documentSearchFilters(
                  documents,
                  mimeTypes: documentMimeTypes,
                  dateFrom: dateFrom,
                  dateTo: dateTo,
                  pathPrefix: pathPrefix,
                ),
          )
          ..limit(limit * SemanticDefaults.candidatePoolMultiple);

    final rows = await query.get();
    return _scoreAndPick(
      rows.map((row) => row.readTable(semantic)).toList(growable: false),
      queryVector,
      minSimilarity,
      limit,
    );
  }

  Expression<bool> _mediaSearchFilters(
    MediaItems m, {
    List<String>? mediaCategories,
    bool? isScreenshot,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  }) {
    Expression<bool> where = const Constant(true);
    if (mediaCategories != null && mediaCategories.isNotEmpty) {
      where = where & m.category.isIn(mediaCategories);
    }
    if (isScreenshot != null) {
      where = where & m.isScreenshot.equals(isScreenshot);
    }
    if (dateFrom != null) {
      where = where & m.dateModified.isBiggerOrEqualValue(dateFrom);
    }
    if (dateTo != null) {
      where = where & m.dateModified.isSmallerOrEqualValue(dateTo);
    }
    if (pathPrefix != null && pathPrefix.isNotEmpty) {
      where = where & m.relativePath.like('$pathPrefix%');
    }
    return where;
  }

  Expression<bool> _documentSearchFilters(
    Documents d, {
    List<String>? mimeTypes,
    int? dateFrom,
    int? dateTo,
    String? pathPrefix,
  }) {
    Expression<bool> where = const Constant(true);
    if (mimeTypes != null && mimeTypes.isNotEmpty) {
      where = where & d.mimeType.isIn(mimeTypes);
    }
    if (dateFrom != null) {
      where = where & d.dateModified.isBiggerOrEqualValue(dateFrom);
    }
    if (dateTo != null) {
      where = where & d.dateModified.isSmallerOrEqualValue(dateTo);
    }
    if (pathPrefix != null && pathPrefix.isNotEmpty) {
      where = where & d.relativePath.like('$pathPrefix%');
    }
    return where;
  }

  /// Decodes each row's vector, computes cosine against [queryVector], and
  /// keeps the top [limit] at-or-above [minSimilarity], deterministically
  /// (similarity desc â†’ stableKey asc). Malformed rows are skipped, never
  /// thrown (AGENTS.md Â§19).
  List<SemanticMatch> _scoreAndPick(
    List<SemanticEmbedding> rows,
    List<double> queryVector,
    double minSimilarity,
    int limit,
  ) {
    final scored = <SemanticMatch>[];
    for (final row in rows) {
      final vector = VectorCodec.decode(row.embeddingData);
      if (vector.length != row.dimensions) continue;
      final similarity = VectorMath.cosine(queryVector, vector);
      if (similarity == null || similarity < minSimilarity) continue;
      scored.add(
        SemanticMatch(
          stableKey: row.stableKey,
          contentType: row.contentType,
          similarity: similarity,
        ),
      );
    }
    scored.sort((a, b) {
      final bySim = b.similarity.compareTo(a.similarity);
      if (bySim != 0) return bySim;
      return a.stableKey.compareTo(b.stableKey);
    });
    return scored.take(limit).toList(growable: false);
  }
}
