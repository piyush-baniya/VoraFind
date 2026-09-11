import '../platform/content_access_models.dart' show ContentCategory;

/// Result of interpreting simple, unambiguous words in a query.
class QueryInterpretation {
  const QueryInterpretation({
    required this.keywords,
    required this.categories,
    required this.isScreenshot,
  });

  /// Tokens that are not filter words and remain keyword searches.
  final List<String> keywords;

  /// Media-type filter words seen (`photo`/`video`/`music` etc.).
  /// Empty when the query says nothing about media type.
  final List<ContentCategory> categories;

  /// True when a screenshot word was seen ('screenshot'/'screenshots').
  /// Null only means "no screenshot word" — never a false negative
  /// classification of an arbitrary image.
  final bool? isScreenshot;
}

/// Lightweight, deterministic interpretation of a few obvious words in a
/// query (docs `search.md` §"Interpretation").
///
/// NOT a natural-language parser. This class maps a fixed vocabulary to typed
/// filters, removes those words from the keyword tokens, and prefers to let
/// everything else fall through to keyword matching. If a word is ambiguous it
/// stays a keyword — never a guess.
abstract final class SearchQueryInterpreter {
  static const _screenshotWords = {'screenshot', 'screenshots'};
  static const _imageWords = {'image', 'images', 'photo', 'photos'};
  static const _videoWords = {'video', 'videos'};
  static const _audioWords = {'audio', 'song', 'songs', 'music'};

  /// Applies the vocabulary above to an already-normalized [tokens] list.
  ///
  /// The returned [QueryInterpretation.keywords] never re-includes a consumed
  /// filter word, so `"screenshot flutter"` runs a screenshot filter plus the
  /// keyword "flutter" — it does not additionally fuzzy-match filenames that
  /// happen to contain the literal word "screenshot". This is the documented,
  /// conservative behavior (an explicit `categories`/`isScreenshot` in
  /// [SearchQuery] overrides interpretation entirely).
  static QueryInterpretation interpret(List<String> tokens) {
    final keywords = <String>[];
    final categories = <ContentCategory>[];
    var screenshotRequested = false;

    for (final token in tokens) {
      if (_screenshotWords.contains(token)) {
        screenshotRequested = true;
      } else if (_imageWords.contains(token)) {
        _addUnique(categories, ContentCategory.images);
      } else if (_videoWords.contains(token)) {
        _addUnique(categories, ContentCategory.videos);
      } else if (_audioWords.contains(token)) {
        _addUnique(categories, ContentCategory.audio);
      } else {
        keywords.add(token);
      }
    }

    return QueryInterpretation(
      keywords: keywords,
      categories: categories,
      isScreenshot: screenshotRequested ? true : null,
    );
  }

  static void _addUnique(List<ContentCategory> target, ContentCategory value) {
    if (!target.contains(value)) target.add(value);
  }
}
