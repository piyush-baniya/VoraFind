import '../platform/content_access_models.dart' show ContentCategory;
import 'search_field.dart';

/// A ranked search result — the settled answer the UI renders.
///
/// Deliberately UI-shaped and free of Drift row types: the UI never touches
/// `MediaItem`/database objects. Every field is a plain value, unchanged from
/// what the index stores (or null when the metadata was not present).
class SearchResult {
  const SearchResult({
    required this.stableKey,
    required this.contentUri,
    required this.displayName,
    required this.category,
    required this.volumeName,
    required this.mediaStoreId,
    required this.title,
    required this.mimeType,
    required this.sizeBytes,
    required this.dateModified,
    required this.relativePath,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.isScreenshot,
    required this.score,
    required this.matches,
  });

  final String stableKey;
  final String contentUri;
  final String displayName;
  final ContentCategory category;
  final String volumeName;
  final int mediaStoreId;
  final String? title;
  final String? mimeType;
  final int? sizeBytes;
  final int? dateModified;
  final String? relativePath;
  final int? width;
  final int? height;
  final int? durationMs;
  final bool? isScreenshot;

  /// Deterministic relevance score from [SearchRanker]. Higher is better.
  /// Ordering is `score desc → dateModified desc → stableKey asc`.
  final int score;

  /// Why this row matched. Empty for filter-only results.
  final List<MatchInfo> matches;
}

/// Settled value of a search attempt: the ranked results, or an empty set for
/// an idle/empty query.
class SearchOutcome {
  const SearchOutcome({this.results = const []});

  const SearchOutcome.empty() : results = const [];

  final List<SearchResult> results;
}
