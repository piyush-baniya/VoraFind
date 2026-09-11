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

/// A document body type a query can pin documents to.
///
/// Mapped from natural words ("pdf", "txt", "markdown") by the interpreter and
/// resolved against `documents.mime_type` in the document repository. Media
/// (MediaStore) candidates are excluded entirely when a type is pinned —
/// "find pdfs" must never return photos.
enum SearchDocumentType {
  pdf,
  text,
  markdown;

  /// MIME values that satisfy this type. A document matches when its MIME is
  /// in this set (markdown accepts both common wire spellings).
  List<String> get mimeTypes => switch (this) {
    SearchDocumentType.pdf => const ['application/pdf'],
    SearchDocumentType.text => const ['text/plain'],
    SearchDocumentType.markdown => const ['text/markdown', 'text/x-markdown'],
  };
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
    this.documentTypes,
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

  /// Explicit document body-type filter (PDF / plain text / markdown). When
  /// non-empty only indexed documents with a matching MIME are considered and
  /// media candidates are excluded. Takes precedence over type words
  /// interpreted from [text].
  final Set<SearchDocumentType>? documentTypes;

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
      maxDurationMs != null ||
      (documentTypes != null && documentTypes!.isNotEmpty);
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
    this.documentTypes = const {},
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

  /// Effective document body-type filter; empty means "all documents".
  final Set<SearchDocumentType> documentTypes;

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
      maxDurationMs != null ||
      documentTypes.isNotEmpty;
}
