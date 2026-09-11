import '../database/app_database.dart' show MediaItem;
import '../database/document_repository.dart';
import '../database/media_repository.dart';
import '../platform/content_access_models.dart' show ContentCategory;
import '../semantic/embedding_provider.dart';
import '../semantic/semantic_models.dart';
import '../semantic/semantic_repository.dart';
import 'search_error.dart';
import 'search_interpreter.dart';
import 'search_normalizer.dart';
import 'search_query.dart';
import 'search_ranker.dart';
import 'search_result.dart';

/// Orchestrates one search: normalize → interpret → validate → retrieve
/// candidates → rank → shape results (docs `search.md` §Architecture).
///
/// The repository is responsible only for efficient candidate retrieval;
/// everything user-facing and ranking-related lives here so future retrieval
/// sources (OCR text, semantic/vector) can plug in below this class without a
/// rewrite.
///
/// When a [SemanticSearchRepository] and [EmbeddingProvider] are supplied,
/// every query that carries keyword tokens also produces a query embedding;
/// semantic candidates are merged with keyword candidates before ranking so
/// exact keyword matches still outrank weak semantic recall (docs
/// `semantic-search.md` §Hybrid search).
class SearchService {
  const SearchService({
    required this.repository,
    this.documentRepository,
    this.semanticSearchRepository,
    this.embeddingProvider,
    this.nowSeconds,
  });

  final MediaRepository repository;
  final DocumentRepository? documentRepository;

  /// Search-side vector retrieval. When null, search degrades to pure
  /// keyword/OCR/document matching — never an error.
  final SemanticSearchRepository? semanticSearchRepository;

  /// Embedding model used to turn the query into a vector. When null, no
  /// query embedding is generated and semantic retrieval is skipped.
  final EmbeddingProvider? embeddingProvider;

  /// Injectable clock (epoch seconds) used to resolve time words like
  /// "recent"/"this month" deterministically. Null → time words stay keywords.
  final int Function()? nowSeconds;

  /// Runs [query] against the local index and returns at most
  /// `query.limit` (bounded by [SearchLimits]) ranked results.
  ///
  /// When the query carries keyword tokens, candidate rows are retrieved from
  /// metadata (`searchable_text`), current OCR text (`ocr_content`), and
  /// documents (`documents` + `document_content`), merged and deduplicated by
  /// stable key, and ranked together so body-text matches can surface files
  /// the filename never mentions.
  ///
  /// Errors are surfaced as [SearchException]: invalid queries are rejected
  /// before any SQL runs, and database failures are wrapped from raw Drift
  /// errors. User query text never leaks into error messages.
  Future<List<SearchResult>> search(SearchQuery query) async {
    final prepared = prepare(query);
    if (!prepared.hasKeyword && !prepared.hasFilters) {
      return const [];
    }

    final candidates = await _retrieve(prepared);
    return const SearchRanker().rank(candidates, prepared);
  }

  /// Retrieves candidates through the repositories, wrapping any database error
  /// in a user-safe [SearchException.database].
  Future<List<SearchCandidate>> _retrieve(
    NormalizedSearchQuery prepared,
  ) async {
    try {
      final docRepo = documentRepository;
      final semRepo = semanticSearchRepository;
      final embed = embeddingProvider;
      final includeDocs = docRepo != null && _mayIncludeDocuments(prepared);
      // A pinned document type ("find pdfs") excludes MediaStore rows by
      // definition — skip media retrieval entirely instead of filtering rows.
      final pinnedDocumentTypes = prepared.documentTypes.isNotEmpty;

      // Semantic retrieval requires both a repository and an embedding model,
      // and is skipped for filter-only queries (no tokens to embed) and for
      // document-pinned queries (the document index is the only place that
      // matters, and it is already covered by keyword search there).
      final runSemantic =
          prepared.hasKeyword &&
          semRepo != null &&
          embed != null &&
          embed.isAvailable &&
          !pinnedDocumentTypes;

      if (!prepared.hasKeyword) {
        if (pinnedDocumentTypes) {
          final docs = includeDocs
              ? await docRepo.searchDocumentCandidates(prepared)
              : const <DocumentSearchMatch>[];
          return [
            for (final match in docs) SearchCandidate(document: match.document),
          ];
        }
        final mediaFuture = repository.searchCandidates(prepared);
        final docFuture = includeDocs
            ? docRepo.searchDocumentCandidates(prepared)
            : Future.value(const <DocumentSearchMatch>[]);
        final semanticFuture = runSemantic
            ? _semanticCandidates(prepared, semRepo, embed)
            : Future.value(const <SemanticMatch>[]);

        final (media, docs, semantic) = await (
          mediaFuture,
          docFuture,
          semanticFuture,
        ).wait;
        return [
          for (final row in media) SearchCandidate(item: row),
          for (final match in docs) SearchCandidate(document: match.document),
          for (final match in semantic)
            SearchCandidate(
              semanticKey: match.stableKey,
              semanticSimilarity: match.similarity,
            ),
        ];
      }

      final mediaFuture = pinnedDocumentTypes
          ? Future.value(const <MediaItem>[])
          : repository.searchCandidates(prepared);
      final ocrFuture = pinnedDocumentTypes
          ? Future.value(const <OcrSearchMatch>[])
          : repository.searchOcrCandidates(prepared);
      final docMetaFuture = includeDocs
          ? docRepo.searchDocumentCandidates(prepared)
          : Future.value(const <DocumentSearchMatch>[]);
      final docContentFuture = includeDocs
          ? docRepo.searchDocumentContentCandidates(prepared)
          : Future.value(const <DocumentSearchMatch>[]);
      final semanticFuture = runSemantic
          ? _semanticCandidates(prepared, semRepo, embed)
          : Future.value(const <SemanticMatch>[]);

      final (media, ocr, docMeta, docContent, semantic) = await (
        mediaFuture,
        ocrFuture,
        docMetaFuture,
        docContentFuture,
        semanticFuture,
      ).wait;

      return _merge(
        metadata: media,
        ocr: ocr,
        docMetadata: docMeta,
        docContent: docContent,
        semantic: semantic,
      );
    } catch (_) {
      throw const SearchException.database();
    }
  }

  static bool _mayIncludeDocuments(NormalizedSearchQuery query) {
    if (query.isScreenshot == true) return false;
    if (query.minDurationMs != null || query.maxDurationMs != null) {
      return false;
    }
    if (query.documentTypes.isNotEmpty) return true;
    if (query.categories.isEmpty) return true;
    return query.categories.any((c) => c.name == 'documents');
  }

  /// Merges bounded candidate pools into one candidate list, deduplicated by
  /// stable key.
  static List<SearchCandidate> _merge({
    required List<MediaItem> metadata,
    required List<OcrSearchMatch> ocr,
    required List<DocumentSearchMatch> docMetadata,
    required List<DocumentSearchMatch> docContent,
    required List<SemanticMatch> semantic,
  }) {
    final byKey = <String, SearchCandidate>{};
    final order = <String>[];
    for (final row in metadata) {
      byKey[row.stableKey] = SearchCandidate(item: row);
      order.add(row.stableKey);
    }
    for (final match in ocr) {
      final key = match.item.stableKey;
      final existing = byKey[key];
      byKey[key] = SearchCandidate(
        item: existing?.item ?? match.item,
        ocrText: match.normalizedText,
      );
      if (existing == null) order.add(key);
    }

    for (final match in docMetadata) {
      final key = match.document.stableKey;
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = SearchCandidate(
          document: match.document,
          documentText: match.normalizedText,
        );
        order.add(key);
      }
    }
    for (final match in docContent) {
      final key = match.document.stableKey;
      final existing = byKey[key];
      byKey[key] = SearchCandidate(
        document: existing?.document ?? match.document,
        documentText: match.normalizedText ?? existing?.documentText,
      );
      if (existing == null) order.add(key);
    }
    for (final match in semantic) {
      final key = match.stableKey;
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = SearchCandidate(
          semanticKey: key,
          semanticSimilarity: match.similarity,
        );
        order.add(key);
      } else if (existing.semanticSimilarity == null) {
        byKey[key] = SearchCandidate(
          item: existing.item,
          document: existing.document,
          ocrText: existing.ocrText,
          documentText: existing.documentText,
          semanticKey: key,
          semanticSimilarity: match.similarity,
        );
      }
    }

    return [for (final key in order) byKey[key]!];
  }

  /// Embeds the query and retrieves semantic candidates from the vector store.
  /// Never throws on semantic failure — returns an empty list so keyword
  /// results still surface (docs `semantic-search.md` §Hybrid search).
  Future<List<SemanticMatch>> _semanticCandidates(
    NormalizedSearchQuery prepared,
    SemanticSearchRepository? semRepo,
    EmbeddingProvider? embed,
  ) async {
    if (semRepo == null || embed == null || !embed.isAvailable) {
      return const <SemanticMatch>[];
    }
    try {
      final tokens = prepared.tokens;
      final queryText = tokens.join(' ');
      final queryVector = await embed.embed(queryText);
      if (queryVector.isEmpty) return const <SemanticMatch>[];
      final mimeTypes = prepared.documentTypes
          .expand((t) => t.mimeTypes)
          .toList();
      return await semRepo.retrieveSemanticCandidates(
        queryVector: queryVector,
        modelId: embed.modelId,
        dimensions: queryVector.length,
        maxResults: prepared.limit * SemanticDefaults.candidatePoolMultiple,
        includeMedia: !prepared.documentTypes.isNotEmpty,
        includeDocuments: _mayIncludeDocuments(prepared),
        mediaCategories: prepared.categories.map((c) => c.name).toList(),
        isScreenshot: prepared.isScreenshot,
        documentMimeTypes: mimeTypes.isNotEmpty ? mimeTypes : null,
        dateFrom: prepared.dateFrom,
        dateTo: prepared.dateTo,
        pathPrefix: prepared.pathPrefix,
      );
    } catch (_) {
      return const <SemanticMatch>[];
    }
  }

  /// Validates and normalizes [query]. Public and pure for unit testing.
  ///
  /// Numeric bounds are checked for sanity and non-negative values; inverted
  /// ranges raise [SearchException.invalidQuery]. The result limit is clamped
  /// into `[1, SearchLimits.maxLimit]`. Interpretation (screenshot/media-type
  /// words) is applied only where no explicit filter already pins the value.
  NormalizedSearchQuery prepare(SearchQuery query) {
    final limit = _boundedLimit(query.limit);

    final rawTokens = SearchNormalizer.tokens(query.text);

    final explicitCategories =
        query.categories != null && query.categories!.isNotEmpty;
    final now = nowSeconds?.call();
    final interpretation = SearchQueryInterpreter.interpret(
      rawTokens,
      nowEpochSeconds: now,
    );
    final categories = explicitCategories
        ? List<ContentCategory>.of(query.categories!)
        : interpretation.categories;
    final isScreenshot = query.isScreenshot ?? interpretation.isScreenshot;

    // Screenshot queries never include documents, so a pinned document type
    // would silently produce zero results — drop the type pins instead.
    final interpretedDocumentTypes = isScreenshot == true
        ? const <SearchDocumentType>{}
        : interpretation.documentTypes;
    final documentTypes =
        (query.documentTypes != null && query.documentTypes!.isNotEmpty)
        ? Set<SearchDocumentType>.of(query.documentTypes!)
        : interpretedDocumentTypes;

    // Time words apply only where no explicit date filter pins the range.
    final explicitDateRange = query.dateFrom != null || query.dateTo != null;
    final dateFrom = explicitDateRange
        ? query.dateFrom
        : interpretation.dateFrom;
    final dateTo = explicitDateRange ? query.dateTo : interpretation.dateTo;
    if (dateFrom != null && dateFrom < 0) {
      throw const SearchException.invalidQuery();
    }
    if (dateTo != null && dateTo < 0) {
      throw const SearchException.invalidQuery();
    }
    if (dateFrom != null && dateTo != null && dateFrom > dateTo) {
      throw const SearchException.invalidQuery('inverted date range');
    }

    final minSizeBytes = query.minSizeBytes;
    final maxSizeBytes = query.maxSizeBytes;
    if (minSizeBytes != null && minSizeBytes < 0) {
      throw const SearchException.invalidQuery();
    }
    if (maxSizeBytes != null && maxSizeBytes < 0) {
      throw const SearchException.invalidQuery();
    }
    if (minSizeBytes != null &&
        maxSizeBytes != null &&
        minSizeBytes > maxSizeBytes) {
      throw const SearchException.invalidQuery('inverted size range');
    }

    final minDurationMs = query.minDurationMs;
    final maxDurationMs = query.maxDurationMs;
    if (minDurationMs != null && minDurationMs < 0) {
      throw const SearchException.invalidQuery();
    }
    if (maxDurationMs != null && maxDurationMs < 0) {
      throw const SearchException.invalidQuery();
    }
    if (minDurationMs != null &&
        maxDurationMs != null &&
        minDurationMs > maxDurationMs) {
      throw const SearchException.invalidQuery('inverted duration range');
    }

    final trimmedPathPrefix = query.pathPrefix?.trim();
    final effectivePathPrefix =
        (trimmedPathPrefix == null || trimmedPathPrefix.isEmpty)
        ? null
        : trimmedPathPrefix.replaceFirst(RegExp(r'^/+'), '');

    return NormalizedSearchQuery(
      tokens: interpretation.keywords,
      categories: categories,
      isScreenshot: isScreenshot,
      dateFrom: dateFrom,
      dateTo: dateTo,
      minSizeBytes: minSizeBytes,
      maxSizeBytes: maxSizeBytes,
      pathPrefix: effectivePathPrefix,
      minDurationMs: minDurationMs,
      maxDurationMs: maxDurationMs,
      documentTypes: documentTypes,
      limit: limit,
    );
  }

  static int _boundedLimit(int? requested) {
    if (requested == null) return SearchLimits.defaultLimit;
    if (requested < 1) return 1;
    if (requested > SearchLimits.maxLimit) return SearchLimits.maxLimit;
    return requested;
  }
}
