/// A metadata field a keyword can match against.
///
/// The order of declaration is not significance — relevance comes from
/// `SearchRanker.fieldWeight` — but this enum is the single vocabulary for
/// *where* a term matched, used by [MatchInfo] and the future "why this
/// matches" UI.
enum SearchField {
  displayName,
  title,
  relativePath,
  bucketDisplayName,
  artist,
  album,
  albumArtist,
  genre,

  /// Text recognized in an image body (OCR). Weighted between folder context
  /// and title by [SearchRanker] — see `docs/search.md` §Ranking.
  ocrText,

  /// Text extracted from a local document body (PDF or plain text).
  documentText,

  /// Semantic/vector similarity match — the row was retrieved because its
  /// stored embedding is close to the query embedding, not because of a
  /// keyword hit. Weighted by [SearchRanker] via [SemanticDefaults].
  semantic,
}

/// How strongly one token matched one field value.
enum MatchStrength {
  /// The token equals a whole normalized word of the field value.
  exact,

  /// The token is a prefix of a normalized word of the field value.
  prefix,

  /// The token appears as a substring of a normalized word (strongest partial
  /// match we accept; no fuzzy/free-wildcard matching).
  substring,
}

/// One `(field, token, strength)` match for a result.
///
/// Minimal and deterministic on purpose: the future UI can render
///
/// ```text
/// Matched filename: flutter, error
/// ```
///
/// straight from these entries without a second query or a redesign of
/// [SearchResult].
class MatchInfo {
  const MatchInfo({
    required this.field,
    required this.token,
    required this.strength,
  });

  final SearchField field;
  final String token;
  final MatchStrength strength;
}
