/// Vocabulary-safe normalization for search text and indexed field values.
///
/// The same normalization is applied on both sides of a match — query tokens
/// and the stored `searchable_text` of a row — so a token can only ever match
/// a value that went through identical rules. This is deliberately
/// *non-destructive*: no stemming, no stop-word lists, no transliteration.
/// Only case folding and separator handling happen (AGENTS.md / `docs/search.md`).
///
/// Since schema v4 the folding is Unicode-aware: letters and digits from any
/// script survive, which OCR content requires (Prompt #8 §20). The stored
/// projections and query tokens are produced by the identical routine, so
/// matching stays byte-exact, and `%`/`_` are still removed on every input
/// (wildcard-safe).
abstract final class SearchNormalizer {
  /// A run of anything that is not a Unicode letter or digit.
  static final RegExp _separator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Folds [input] to lowercase and replaces every run of characters that are
  /// not Unicode letters or digits with a single space, then trims.
  ///
  /// Consequences (documented):
  /// * `%` and `_` are removed, so normalized text can never contain LIKE
  ///   wildcard characters — substring matching on it is wildcard-safe.
  /// * Separators like `_`, `-`, `.`, and spaces all become word boundaries,
  ///   which is what lets `citizenship_front.jpg` match the tokens
  ///   "citizenship" and "front".
  /// * Unicode letters and digits survive unchanged (`café 東京` stays
  ///   searchable), while quotes and `%`/`_` are still impossible, so the
  ///   literal `LIKE`/`instr` embedding in the repository stays injection-safe.
  static String canonical(String input) {
    if (input.isEmpty) return '';
    return input.toLowerCase().replaceAll(_separator, ' ').trim();
  }

  /// Splits normalized [input] into its non-empty words.
  ///
  /// `canonical("Citizenship_Front.JPG")` → `["citizenship", "front", "jpg"]`.
  static List<String> words(String input) {
    final value = canonical(input);
    if (value.isEmpty) return const [];
    return value.split(' ').toList(growable: false);
  }

  /// Splits [query] into normalized, non-empty tokens.
  ///
  /// `"  Flutter   ERROR "` → `["flutter", "error"]`.
  static List<String> tokens(String query) => words(query);

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
