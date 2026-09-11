import '../platform/content_access_models.dart' show ContentCategory;

/// Bounds that keep search result sets predictable (docs `search.md`).
///
/// Searches are always bounded: the repository returns at most
/// [candidatePool] rows, and the service/user-facing API returns at most
/// `limit` (defaulted to [defaultLimit], clamped to [maxLimit]) ranked results.
abstract final class SearchLimits {
  static const int defaultLimit = 50;
  static const int maxLimit = 200;

  /// Candidate pool is a bounded multiple of the result limit so Dart-side
  /// ranking has slack to promote high-relevance rows that SQL ordering alone
  /// would have cut off — never unbounded.
  static const int candidatePoolMultiple = 4;

  /// Absolute ceiling for the candidate pool regardless of [maxLimit].
  static const int maxCandidatePool = 400;
}

/// A user-facing search request.
///
/// `text` is the raw (un-normalized) query. Filters are typed and applied in
/// SQLite before ranking; keyword interpretation (e.g. "screenshot" →
/// screenshot filter) happens in `SearchQueryPreparer`, never here.
///
/// Not every conceivable filter is modeled: only the ones that map cleanly to
/// the current `media_items` schema. Extensible fields (new filters) can be
/// added without breaking existing callers because construction is by named
/// argument.
class SearchQuery {
  const SearchQuery({
    this.text = '',
    this.categories,
    this.isScreenshot,
    this.dateFrom,
    this.dateTo,
    this.minSizeBytes,
    this.maxSizeBytes,
    this.pathPrefix,
    this.minDurationMs,
    this.maxDurationMs,
    this.limit,
  });

  const SearchQuery.empty() : this();

  /// Raw user text; normalized and tokenized by the search service.
  final String text;

  /// Explicit media-type filter. When non-empty it takes precedence over any
  /// media-type terms interpreted from [text].
  final List<ContentCategory>? categories;

  /// Explicit screenshot filter. When non-null it takes precedence over the
  /// interpreted "screenshot" term.
  final bool? isScreenshot;

  /// Inclusive lower bound on `dateModified` (epoch seconds).
  final int? dateFrom;

  /// Inclusive upper bound on `dateModified` (epoch seconds).
  final int? dateTo;

  final int? minSizeBytes;
  final int? maxSizeBytes;

  /// Case-insensitive prefix of `relativePath` (leading slashes ignored).
  final String? pathPrefix;

  final int? minDurationMs;
  final int? maxDurationMs;

  /// Result limit; null → [SearchLimits.defaultLimit]. Clamped to
  /// `[1, SearchLimits.maxLimit]` by the search service.
  final int? limit;

  /// True when anything is being requested (a query that would hit the index).
  ///
  /// Used by the UI to decide between idle and searching states.
  bool get hasContent =>
      text.trim().isNotEmpty ||
      (categories != null && categories!.isNotEmpty) ||
      isScreenshot != null ||
      dateFrom != null ||
      dateTo != null ||
      minSizeBytes != null ||
      maxSizeBytes != null ||
      pathPrefix != null ||
      minDurationMs != null ||
      maxDurationMs != null;
}

/// The prepared, validated search request after normalization and
/// interpretation.
///
/// This is the object the repository consumes to build its SQL and the ranker
/// consumes for matching — it is intentionally free of UI concerns.
class NormalizedSearchQuery {
  const NormalizedSearchQuery({
    required this.tokens,
    required this.categories,
    required this.isScreenshot,
    required this.dateFrom,
    required this.dateTo,
    required this.minSizeBytes,
    required this.maxSizeBytes,
    required this.pathPrefix,
    required this.minDurationMs,
    required this.maxDurationMs,
    required this.limit,
  });

  /// Normalized keyword tokens (lowercased, alphanumeric only). Empty for a
  /// filter-only search.
  final List<String> tokens;

  /// Effective media-type filter; empty list means "all categories".
  final List<ContentCategory> categories;

  /// Effective screenshot filter; null means "no screenshot constraint".
  final bool? isScreenshot;

  final int? dateFrom;
  final int? dateTo;
  final int? minSizeBytes;
  final int? maxSizeBytes;

  /// Normalized path prefix (leading slashes removed, LIKE wildcards escaped).
  final String? pathPrefix;

  final int? minDurationMs;
  final int? maxDurationMs;

  /// Validated, bounded result limit.
  final int limit;

  /// True when at least one keyword token survived interpretation.
  bool get hasKeyword => tokens.isNotEmpty;

  /// True when any filter constrains the index.
  bool get hasFilters =>
      categories.isNotEmpty ||
      isScreenshot != null ||
      dateFrom != null ||
      dateTo != null ||
      minSizeBytes != null ||
      maxSizeBytes != null ||
      pathPrefix != null ||
      minDurationMs != null ||
      maxDurationMs != null;
}
