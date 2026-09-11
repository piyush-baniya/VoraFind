import '../database/app_database.dart' show MediaItem;
import '../database/document_repository.dart';
import '../database/media_repository.dart';
import '../platform/content_access_models.dart' show ContentCategory;
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
class SearchService {
  const SearchService({required this.repository, this.documentRepository});

  final MediaRepository repository;
  final DocumentRepository? documentRepository;

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
      final includeDocs = docRepo != null && _mayIncludeDocuments(prepared);

      if (!prepared.hasKeyword) {
        final mediaFuture = repository.searchCandidates(prepared);
        final docFuture = includeDocs
            ? docRepo.searchDocumentCandidates(prepared)
            : Future.value(const <DocumentSearchMatch>[]);

        final (media, docs) = await (mediaFuture, docFuture).wait;
        return [
          for (final row in media) SearchCandidate(item: row),
          for (final match in docs) SearchCandidate(document: match.document),
        ];
      }

      final mediaFuture = repository.searchCandidates(prepared);
      final ocrFuture = repository.searchOcrCandidates(prepared);
      final docMetaFuture = includeDocs
          ? docRepo.searchDocumentCandidates(prepared)
          : Future.value(const <DocumentSearchMatch>[]);
      final docContentFuture = includeDocs
          ? docRepo.searchDocumentContentCandidates(prepared)
          : Future.value(const <DocumentSearchMatch>[]);

      final (media, ocr, docMeta, docContent) = await (
        mediaFuture,
        ocrFuture,
        docMetaFuture,
        docContentFuture,
      ).wait;

      return _merge(
        metadata: media,
        ocr: ocr,
        docMetadata: docMeta,
        docContent: docContent,
      );
    } catch (_) {
      throw const SearchException.database();
    }
  }

  static bool _mayIncludeDocuments(NormalizedSearchQuery query) {
    if (query.isScreenshot == true) return false;
    if (query.minDurationMs != null || query.maxDurationMs != null)
      return false;
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

    return [for (final key in order) byKey[key]!];
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
    final interpretation = SearchQueryInterpreter.interpret(rawTokens);
    final categories = explicitCategories
        ? List<ContentCategory>.of(query.categories!)
        : interpretation.categories;
    final isScreenshot = query.isScreenshot ?? interpretation.isScreenshot;

    final dateFrom = query.dateFrom;
    final dateTo = query.dateTo;
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
