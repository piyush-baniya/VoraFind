/// Vocabulary-safe normalization for search text and indexed field values.
///
/// The same normalization is applied on both sides of a match — query tokens
/// and the stored `searchable_text` of a row — so a token can only ever match
/// a value that went through identical rules. This is deliberately
/// *non-destructive*: no stemming, no stop-word lists, no transliteration.
/// Only case folding and separator handling happen (AGENTS.md / `docs/search.md`).
abstract final class SearchNormalizer {
  /// Folds [input] to lowercase and replaces every run of non-alphanumeric
  /// characters with a single space, then trims.
  ///
  /// Consequences (documented):
  /// * `%` and `_` are removed, so normalized text can never contain LIKE
  ///   wildcard characters — substring matching on it is wildcard-safe.
  /// * Separators like `_`, `-`, `.`, and spaces all become word boundaries,
  ///   which is what lets `citizenship_front.jpg` match the tokens
  ///   "citizenship" and "front".
  static String canonical(String input) {
    if (input.isEmpty) return '';
    return input.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();
  }

  /// Splits [query] into normalized, non-empty tokens.
  ///
  /// `"  Flutter   ERROR "` → `["flutter", "error"]`.
  static List<String> tokens(String query) {
    final value = canonical(query);
    if (value.isEmpty) return const [];
    return value.split(' ').toList(growable: false);
  }

  /// Normalizes several field values into one canonical, space-joined string
  /// for the stored `searchable_text` row value.
  ///
  /// Null and empty fields are skipped. This is a *retrieval* projection only —
  /// per-field relevance is recomputed by the ranker from the original columns,
  /// so concatenating here does not flatten search quality.
  static String storageText(Iterable<String?> fields) {
    var any = false;
    final buffer = StringBuffer();
    for (final field in fields) {
      if (field == null || field.isEmpty) continue;
      if (any) buffer.write(' ');
      any = true;
      buffer.write(field);
    }
    return canonical(buffer.toString());
  }
}
