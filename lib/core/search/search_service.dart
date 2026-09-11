import '../database/app_database.dart';
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
  const SearchService({required this.repository});

  final MediaRepository repository;

  /// Runs [query] against the local index and returns at most
  /// `query.limit` (bounded by [SearchLimits]) ranked results.
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

  /// Retrieves candidates through the repository, wrapping any database error
  /// in a user-safe [SearchException.database].
  Future<List<MediaItem>> _retrieve(NormalizedSearchQuery prepared) async {
    try {
      return await repository.searchCandidates(prepared);
    } catch (_) {
      throw const SearchException.database();
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
