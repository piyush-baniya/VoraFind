import 'package:drift/drift.dart';

import '../documents/document_models.dart';
import '../platform/content_access_models.dart' show DocumentGrant;
import '../search/search_normalizer.dart';
import '../search/search_query.dart';
import 'app_database.dart';
import 'document_content_table.dart';
import 'documents_table.dart';

/// Snapshot of indexed SAF documents for progress surfaces.
class DocumentIndexStats {
  const DocumentIndexStats({
    required this.total,
    required this.accessible,
    required this.completed,
    required this.empty,
    required this.failed,
    required this.unsupported,
  });

  final int total;
  final int accessible;
  final int completed;
  final int empty;
  final int failed;
  final int unsupported;

  int get processed => completed + empty + unsupported;
}

class DocumentContentRow {
  const DocumentContentRow({
    required this.stableKey,
    required this.status,
    required this.sourceRevision,
    required this.truncated,
    required this.updatedAt,
    this.errorCode,
    this.normalizedText,
  });

  final String stableKey;
  final DocumentContentStatus status;
  final int sourceRevision;
  final bool truncated;
  final int updatedAt;
  final String? errorCode;
  final String? normalizedText;
}

class DocumentSearchMatch {
  const DocumentSearchMatch({required this.document, this.normalizedText});

  final Document document;
  final String? normalizedText;
}

/// Data-access boundary for SAF documents and extracted text.
abstract interface class DocumentRepository {
  Future<void> upsertGrant(DocumentGrant grant, {required int nowSeconds});

  Future<void> markGrantInaccessible(String treeUri, {required int nowSeconds});

  Future<List<SafGrant>> listGrants();

  Future<Document?> fetchByStableKey(String stableKey);

  Future<UpsertDocumentDelta> upsertDocuments(
    Iterable<DiscoveredDocument> documents, {
    required int nowSeconds,
  });

  Future<void> markTreeInaccessible(String treeUri, {required int nowSeconds});

  /// Deletes documents in [treeUri] whose keys are not in [seenKeys].
  /// Only call after a complete, non-truncated enumeration.
  Future<int> deleteMissingFromTree({
    required String treeUri,
    required Set<String> seenKeys,
  });

  Future<List<Document>> findExtractionCandidates({
    required int batchSize,
    required int nowEpochSeconds,
    int retryCooldownSeconds = DocumentDefaults.retryCooldownSeconds,
  });

  Future<void> saveExtractionResult({
    required String stableKey,
    required String? text,
    required DocumentContentStatus status,
    required int sourceRevision,
    required int nowEpochSeconds,
    bool truncated = false,
    String? errorCode,
  });

  Future<DocumentContentRow?> getContent(String stableKey);

  Future<DocumentIndexStats> stats();

  Future<int> count();

  Future<List<DocumentSearchMatch>> searchDocumentCandidates(
    NormalizedSearchQuery query,
  );

  Future<List<DocumentSearchMatch>> searchDocumentContentCandidates(
    NormalizedSearchQuery query,
  );

  Future<void> clearAll();
}

class UpsertDocumentDelta {
  const UpsertDocumentDelta({
    required this.inserted,
    required this.updated,
    required this.unchanged,
  });

  final int inserted;
  final int updated;
  final int unchanged;
}

class DriftDocumentRepository implements DocumentRepository {
  DriftDocumentRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> upsertGrant(
    DocumentGrant grant, {
    required int nowSeconds,
  }) async {
    await _db
        .into(_db.safGrants)
        .insert(
          SafGrantsCompanion.insert(
            treeUri: grant.uri,
            displayName: grant.displayName,
            persisted: grant.persisted,
            accessState: DocumentAccessState.accessible,
            lastSeenAt: nowSeconds,
          ),
          onConflict: DoUpdate(
            (_) => SafGrantsCompanion(
              displayName: Value(grant.displayName),
              persisted: Value(grant.persisted),
              accessState: const Value(DocumentAccessState.accessible),
              lastSeenAt: Value(nowSeconds),
            ),
          ),
        );
  }

  @override
  Future<void> markGrantInaccessible(
    String treeUri, {
    required int nowSeconds,
  }) async {
    await (_db.update(
      _db.safGrants,
    )..where((row) => row.treeUri.equals(treeUri))).write(
      SafGrantsCompanion(
        accessState: const Value(DocumentAccessState.inaccessible),
        lastSeenAt: Value(nowSeconds),
      ),
    );
    await markTreeInaccessible(treeUri, nowSeconds: nowSeconds);
  }

  @override
  Future<List<SafGrant>> listGrants() => _db.select(_db.safGrants).get();

  @override
  Future<Document?> fetchByStableKey(String stableKey) {
    return (_db.select(
      _db.documents,
    )..where((row) => row.stableKey.equals(stableKey))).getSingleOrNull();
  }

  @override
  Future<UpsertDocumentDelta> upsertDocuments(
    Iterable<DiscoveredDocument> documents, {
    required int nowSeconds,
  }) async {
    final snapshot = List<DiscoveredDocument>.of(documents);
    if (snapshot.isEmpty) {
      return const UpsertDocumentDelta(inserted: 0, updated: 0, unchanged: 0);
    }
    var inserted = 0;
    var updated = 0;
    var unchanged = 0;
    await _db.transaction(() async {
      for (final incoming in snapshot) {
        final existing = await fetchByStableKey(incoming.stableKey);
        if (existing == null) {
          await _db
              .into(_db.documents)
              .insert(_forInsert(incoming, nowSeconds: nowSeconds));
          inserted++;
        } else if (_sameContent(existing, incoming)) {
          await (_db.update(
            _db.documents,
          )..where((row) => row.stableKey.equals(incoming.stableKey))).write(
            DocumentsCompanion(
              accessState: const Value(DocumentAccessState.accessible),
              lastDiscoveredAt: Value(nowSeconds),
              uri: Value(incoming.uri),
              displayName: Value(incoming.displayName),
              relativePath: Value<String?>(incoming.relativePath),
            ),
          );
          unchanged++;
        } else {
          await (_db.update(_db.documents)
                ..where((row) => row.stableKey.equals(incoming.stableKey)))
              .write(_forUpdate(existing, incoming, nowSeconds: nowSeconds));
          updated++;
        }
      }
    });
    return UpsertDocumentDelta(
      inserted: inserted,
      updated: updated,
      unchanged: unchanged,
    );
  }

  @override
  Future<void> markTreeInaccessible(
    String treeUri, {
    required int nowSeconds,
  }) async {
    await (_db.update(
      _db.documents,
    )..where((row) => row.treeUri.equals(treeUri))).write(
      DocumentsCompanion(
        accessState: const Value(DocumentAccessState.inaccessible),
        lastDiscoveredAt: Value(nowSeconds),
      ),
    );
  }

  @override
  Future<int> deleteMissingFromTree({
    required String treeUri,
    required Set<String> seenKeys,
  }) async {
    final rows = await (_db.select(
      _db.documents,
    )..where((row) => row.treeUri.equals(treeUri))).get();
    final missing = [
      for (final row in rows)
        if (!seenKeys.contains(row.stableKey)) row.stableKey,
    ];
    if (missing.isEmpty) return 0;
    const chunk = 200;
    for (var i = 0; i < missing.length; i += chunk) {
      final end = i + chunk > missing.length ? missing.length : i + chunk;
      await (_db.delete(
        _db.documents,
      )..where((row) => row.stableKey.isIn(missing.sublist(i, end)))).go();
    }
    return missing.length;
  }

  @override
  Future<List<Document>> findExtractionCandidates({
    required int batchSize,
    required int nowEpochSeconds,
    int retryCooldownSeconds = DocumentDefaults.retryCooldownSeconds,
  }) async {
    assert(batchSize > 0, 'batchSize must be positive');
    final t = _db.documents;
    final c = _db.documentContent;
    final cooldownCutoff = nowEpochSeconds - retryCooldownSeconds;
    final statement = _db.select(t).join([
      leftOuterJoin(c, c.documentStableKey.equalsExp(t.stableKey)),
    ]);
    statement
      ..where(
        t.accessState.equals(DocumentAccessState.accessible.name) &
            _extractionEligibility(t, c, cooldownCutoff),
      )
      ..orderBy([OrderingTerm.asc(t.stableKey)])
      ..limit(batchSize);
    final rows = await statement.get();
    return rows.map((row) => row.readTable(t)).toList(growable: false);
  }

  Expression<bool> _extractionEligibility(
    Documents t,
    DocumentContent c,
    int cooldownCutoff,
  ) {
    final neverProcessed = c.status.isNull();
    final retryExpiredFailure =
        c.status.equals(DocumentContentStatus.failed.name) &
        c.updatedAt.isSmallerOrEqualValue(cooldownCutoff);
    final stale =
        (c.status.equals(DocumentContentStatus.completed.name) |
            c.status.equals(DocumentContentStatus.empty.name)) &
        c.sourceRevision.isSmallerThan(t.sourceRevision);
    return neverProcessed | retryExpiredFailure | stale;
  }

  @override
  Future<void> saveExtractionResult({
    required String stableKey,
    required String? text,
    required DocumentContentStatus status,
    required int sourceRevision,
    required int nowEpochSeconds,
    bool truncated = false,
    String? errorCode,
  }) async {
    final normalized = text == null ? null : SearchNormalizer.canonical(text);
    await _db
        .into(_db.documentContent)
        .insert(
          DocumentContentCompanion.insert(
            documentStableKey: stableKey,
            rawText: Value<String?>(text),
            normalizedText: Value<String?>(normalized),
            status: status,
            sourceRevision: sourceRevision,
            truncated: Value(truncated),
            createdAt: nowEpochSeconds,
            updatedAt: nowEpochSeconds,
            errorCode: Value<String?>(errorCode),
          ),
          onConflict: DoUpdate(
            (_) => DocumentContentCompanion(
              rawText: Value<String?>(text),
              normalizedText: Value<String?>(normalized),
              status: Value(status),
              sourceRevision: Value(sourceRevision),
              truncated: Value(truncated),
              updatedAt: Value(nowEpochSeconds),
              errorCode: Value<String?>(errorCode),
            ),
          ),
        );
  }

  @override
  Future<DocumentContentRow?> getContent(String stableKey) async {
    final row = await (_db.select(
      _db.documentContent,
    )..where((r) => r.documentStableKey.equals(stableKey))).getSingleOrNull();
    if (row == null) return null;
    return DocumentContentRow(
      stableKey: row.documentStableKey,
      status: row.status,
      sourceRevision: row.sourceRevision,
      truncated: row.truncated,
      updatedAt: row.updatedAt,
      errorCode: row.errorCode,
      normalizedText: row.normalizedText,
    );
  }

  @override
  Future<DocumentIndexStats> stats() async {
    final total = await count();
    final accessibleQuery = _db.selectOnly(_db.documents)
      ..addColumns([countAll()])
      ..where(
        _db.documents.accessState.equals(DocumentAccessState.accessible.name),
      );
    final accessible =
        (await accessibleQuery.getSingle()).read(countAll()) ?? 0;

    var completed = 0;
    var empty = 0;
    var failed = 0;
    var unsupported = 0;
    final byStatus = _db.selectOnly(_db.documentContent)
      ..addColumns([_db.documentContent.status, countAll()])
      ..groupBy([_db.documentContent.status]);
    for (final row in await byStatus.get()) {
      final count = row.read(countAll()) ?? 0;
      switch (row.readWithConverter(_db.documentContent.status)) {
        case DocumentContentStatus.completed:
          completed = count;
        case DocumentContentStatus.empty:
          empty = count;
        case DocumentContentStatus.failed:
          failed = count;
        case DocumentContentStatus.unsupported:
          unsupported = count;
        case null:
          break;
      }
    }
    return DocumentIndexStats(
      total: total,
      accessible: accessible,
      completed: completed,
      empty: empty,
      failed: failed,
      unsupported: unsupported,
    );
  }

  @override
  Future<int> count() async {
    final query = _db.selectOnly(_db.documents)..addColumns([countAll()]);
    return (await query.getSingle()).read(countAll()) ?? 0;
  }

  @override
  Future<List<DocumentSearchMatch>> searchDocumentCandidates(
    NormalizedSearchQuery query,
  ) async {
    if (!_includeDocuments(query)) return const [];
    final t = _db.documents;
    final tokens = query.tokens;
    final pool = _candidatePool(query);
    final statement = _db.select(t)
      ..where(
        (row) =>
            row.accessState.equals(DocumentAccessState.accessible.name) &
            _documentFilters(row, query) &
            (tokens.isEmpty
                ? const Constant(true)
                : _keywordPredicate(row.searchableText, tokens)),
      )
      ..limit(pool);

    if (tokens.isNotEmpty) {
      statement.orderBy([
        (row) => OrderingTerm.desc(
          _coverageExpression('documents.searchable_text', tokens),
        ),
        (row) => OrderingTerm.desc(row.dateModified),
        (row) => OrderingTerm.asc(row.stableKey),
      ]);
    } else {
      statement.orderBy([
        (row) => OrderingTerm.desc(row.dateModified),
        (row) => OrderingTerm.asc(row.stableKey),
      ]);
    }
    final rows = await statement.get();
    return [for (final row in rows) DocumentSearchMatch(document: row)];
  }

  @override
  Future<List<DocumentSearchMatch>> searchDocumentContentCandidates(
    NormalizedSearchQuery query,
  ) async {
    if (!_includeDocuments(query) || !query.hasKeyword) return const [];
    final t = _db.documents;
    final c = _db.documentContent;
    final tokens = query.tokens;
    final pool = _candidatePool(query);
    final statement = _db.select(t).join([
      innerJoin(c, c.documentStableKey.equalsExp(t.stableKey)),
    ]);
    statement
      ..where(
        t.accessState.equals(DocumentAccessState.accessible.name) &
            _documentFilters(t, query) &
            (c.status.equals(DocumentContentStatus.completed.name) |
                c.status.equals(DocumentContentStatus.empty.name)) &
            c.sourceRevision.equalsExp(t.sourceRevision) &
            _keywordPredicate(c.normalizedText, tokens),
      )
      ..orderBy([
        OrderingTerm.desc(
          _coverageExpression('document_content.normalized_text', tokens),
        ),
        OrderingTerm.desc(t.dateModified),
        OrderingTerm.asc(t.stableKey),
      ])
      ..limit(pool);
    final rows = await statement.get();
    return [
      for (final row in rows)
        DocumentSearchMatch(
          document: row.readTable(t),
          normalizedText: row.readTable(c).normalizedText,
        ),
    ];
  }

  @override
  Future<void> clearAll() async {
    await _db.delete(_db.documentContent).go();
    await _db.delete(_db.documents).go();
    await _db.delete(_db.safGrants).go();
  }

  DocumentsCompanion _forInsert(
    DiscoveredDocument incoming, {
    required int nowSeconds,
  }) {
    return DocumentsCompanion.insert(
      stableKey: incoming.stableKey,
      treeUri: incoming.treeUri,
      documentId: incoming.documentId,
      uri: incoming.uri,
      displayName: incoming.displayName,
      mimeType: Value<String?>(incoming.mimeType),
      sizeBytes: Value<int?>(incoming.sizeBytes),
      dateModified: Value<int?>(incoming.dateModified),
      relativePath: Value<String?>(incoming.relativePath),
      contentFingerprint: incoming.contentFingerprint,
      sourceRevision: 1,
      accessState: DocumentAccessState.accessible,
      firstDiscoveredAt: nowSeconds,
      lastDiscoveredAt: nowSeconds,
      searchableText: Value(_searchable(incoming)),
    );
  }

  DocumentsCompanion _forUpdate(
    Document existing,
    DiscoveredDocument incoming, {
    required int nowSeconds,
  }) {
    return DocumentsCompanion(
      uri: Value(incoming.uri),
      displayName: Value(incoming.displayName),
      mimeType: Value<String?>(incoming.mimeType),
      sizeBytes: Value<int?>(incoming.sizeBytes),
      dateModified: Value<int?>(incoming.dateModified),
      relativePath: Value<String?>(incoming.relativePath),
      contentFingerprint: Value(incoming.contentFingerprint),
      sourceRevision: Value(existing.sourceRevision + 1),
      accessState: const Value(DocumentAccessState.accessible),
      lastDiscoveredAt: Value(nowSeconds),
      searchableText: Value(_searchable(incoming)),
    );
  }

  static bool _sameContent(Document existing, DiscoveredDocument incoming) {
    return existing.contentFingerprint == incoming.contentFingerprint &&
        existing.displayName == incoming.displayName &&
        existing.relativePath == incoming.relativePath &&
        existing.uri == incoming.uri;
  }

  static String _searchable(DiscoveredDocument incoming) {
    return SearchNormalizer.storageText([
      incoming.displayName,
      incoming.relativePath,
      incoming.mimeType,
    ]);
  }

  static bool _includeDocuments(NormalizedSearchQuery query) {
    if (query.isScreenshot == true) return false;
    if (query.minDurationMs != null || query.maxDurationMs != null) {
      return false;
    }
    if (query.categories.isEmpty) return true;
    return query.categories.any((category) => category.name == 'documents');
  }

  Expression<bool> _documentFilters(Documents t, NormalizedSearchQuery query) {
    Expression<bool> where = const Constant(true);
    final dateFrom = query.dateFrom;
    if (dateFrom != null) {
      where = where & t.dateModified.isBiggerOrEqualValue(dateFrom);
    }
    final dateTo = query.dateTo;
    if (dateTo != null) {
      where = where & t.dateModified.isSmallerOrEqualValue(dateTo);
    }
    final minSize = query.minSizeBytes;
    if (minSize != null) {
      where = where & t.sizeBytes.isBiggerOrEqualValue(minSize);
    }
    final maxSize = query.maxSizeBytes;
    if (maxSize != null) {
      where = where & t.sizeBytes.isSmallerOrEqualValue(maxSize);
    }
    final pathPrefix = query.pathPrefix;
    if (pathPrefix != null && pathPrefix.isNotEmpty) {
      final escaped = pathPrefix
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      where = where & t.relativePath.like('$escaped%', escapeChar: r'\');
    }
    return where;
  }

  Expression<bool> _keywordPredicate(
    GeneratedColumn<String> column,
    List<String> tokens,
  ) {
    return tokens
        .map((token) => column.like('%$token%'))
        .reduce((a, b) => a | b);
  }

  Expression<int> _coverageExpression(String columnSql, List<String> tokens) {
    final parts = tokens
        .map((token) => "(instr($columnSql, '$token') > 0)")
        .join(' + ');
    if (parts.isEmpty) return CustomExpression<int>('(0)');
    return CustomExpression<int>('($parts)');
  }

  static int _candidatePool(NormalizedSearchQuery query) {
    if (!query.hasKeyword) return query.limit;
    final multiple = query.limit * SearchLimits.candidatePoolMultiple;
    return multiple > SearchLimits.maxCandidatePool
        ? SearchLimits.maxCandidatePool
        : multiple;
  }
}
