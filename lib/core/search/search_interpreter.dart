import '../platform/content_access_models.dart' show ContentCategory;
import 'search_query.dart' show SearchDocumentType;

/// Result of interpreting simple, unambiguous words in a query.
class QueryInterpretation {
  const QueryInterpretation({
    required this.keywords,
    required this.categories,
    required this.isScreenshot,
    this.documentTypes = const <SearchDocumentType>{},
    this.dateFrom,
    this.dateTo,
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

  /// Document body-type words seen (`pdf`, `txt`, `markdown` …). Empty when
  /// the query says nothing about a document type.
  final Set<SearchDocumentType> documentTypes;

  /// Inclusive lower date bound (epoch seconds) from a time word
  /// (`today`/`yesterday`/`this week`/`this month`/`recent`). Null when the
  /// query carries no time word (or no clock was supplied).
  final int? dateFrom;

  /// Inclusive upper date bound (epoch seconds); only `yesterday` produces one.
  final int? dateTo;
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

  /// Generic document words: a category filter (documents), not a body type.
  static const _documentWords = {'document', 'documents', 'doc', 'docs'};

  /// Applies the vocabulary above to an already-normalized [tokens] list.
  ///
  /// The returned [QueryInterpretation.keywords] never re-includes a consumed
  /// filter word, so `"screenshot flutter"` runs a screenshot filter plus the
  /// keyword "flutter" — it does not additionally fuzzy-match filenames that
  /// happen to contain the literal word "screenshot". This is the documented,
  /// conservative behavior (an explicit `categories`/`isScreenshot` in
  /// [SearchQuery] overrides interpretation entirely).
  /// Typed document words: pin the body type (PDF / plain text / markdown).
  /// Bare `md` is accepted for markdown; the word is rare in filenames and
  /// the filter is only applied to document MIME resolution.
  static const _pdfWords = {'pdf', 'pdfs'};
  static const _textWords = {'text', 'txt'};
  static const _markdownWords = {'markdown', 'md'};

  /// Time vocabulary. `this` is consumed only as part of "this week"/"this
  /// month"; bare `week`/`month` stay keywords (common filename words).
  static const _todayWords = {'today'};
  static const _yesterdayWords = {'yesterday'};
  static const _weekWords = {'week'};
  static const _monthWords = {'month'};
  static const _recentWords = {'recent', 'recently'};

  static const int _secondsPerDay = 60 * 60 * 24;

  /// Applies the vocabulary above to an already-normalized [tokens] list.
  ///
  /// The returned [QueryInterpretation.keywords] never re-includes a consumed
  /// filter word, so `"screenshot flutter"` runs a screenshot filter plus the
  /// keyword "flutter" — it does not additionally fuzzy-match filenames that
  /// happen to contain the literal word "screenshot". This is the documented,
  /// conservative behavior (an explicit `categories`/`isScreenshot` in
  /// [SearchQuery] overrides interpretation entirely).
  ///
  /// Time words need a clock: when [nowEpochSeconds] is null they stay
  /// keywords, so interpretation remains fully deterministic and testable.
  static QueryInterpretation interpret(
    List<String> tokens, {
    int? nowEpochSeconds,
  }) {
    final keywords = <String>[];
    final categories = <ContentCategory>[];
    final documentTypes = <SearchDocumentType>{};
    final starts = <int>[];
    final ends = <int?>[];
    var screenshotRequested = false;

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (_screenshotWords.contains(token)) {
        screenshotRequested = true;
      } else if (_imageWords.contains(token)) {
        _addUnique(categories, ContentCategory.images);
      } else if (_videoWords.contains(token)) {
        _addUnique(categories, ContentCategory.videos);
      } else if (_audioWords.contains(token)) {
        _addUnique(categories, ContentCategory.audio);
      } else if (_documentWords.contains(token)) {
        _addUnique(categories, ContentCategory.documents);
      } else if (_pdfWords.contains(token)) {
        documentTypes.add(SearchDocumentType.pdf);
      } else if (_textWords.contains(token)) {
        documentTypes.add(SearchDocumentType.text);
      } else if (_markdownWords.contains(token)) {
        documentTypes.add(SearchDocumentType.markdown);
      } else if (nowEpochSeconds != null && _todayWords.contains(token)) {
        starts.add(_startOfToday(nowEpochSeconds));
        ends.add(null);
      } else if (nowEpochSeconds != null && _yesterdayWords.contains(token)) {
        starts.add(_startOfToday(nowEpochSeconds) - _secondsPerDay);
        ends.add(_startOfToday(nowEpochSeconds));
      } else if (nowEpochSeconds != null && _recentWords.contains(token)) {
        starts.add(_startOfToday(nowEpochSeconds) - 6 * _secondsPerDay);
        ends.add(null);
      } else if (nowEpochSeconds != null &&
          _isThisUnitPhrase(tokens, i, _weekWords)) {
        starts.add(_startOfWeek(nowEpochSeconds));
        ends.add(null);
        i++; // consume the unit word "week" alongside "this"
      } else if (nowEpochSeconds != null &&
          _isThisUnitPhrase(tokens, i, _monthWords)) {
        starts.add(_startOfMonth(nowEpochSeconds));
        ends.add(null);
        i++; // consume the unit word "month" alongside "this"
      } else {
        keywords.add(token);
      }
    }

    return _combineTimeWindows(
      keywords: keywords,
      categories: categories,
      documentTypes: documentTypes,
      isScreenshot: screenshotRequested ? true : null,
      starts: starts,
      ends: ends,
    );
  }

  /// True when [tokens[i]] begins the phrase "this week"/"this month":
  /// `this` at [i] followed by a unit word in [units].
  static bool _isThisUnitPhrase(List<String> tokens, int i, Set<String> units) {
    return tokens[i] == 'this' &&
        i + 1 < tokens.length &&
        units.contains(tokens[i + 1]);
  }

  /// Merges multiple time words into one window: the earliest start wins, and
  /// a bounded word ("yesterday") keeps its end only if it does not precede
  /// the chosen start (which would invert the range).
  static QueryInterpretation _combineTimeWindows({
    required List<String> keywords,
    required List<ContentCategory> categories,
    required Set<SearchDocumentType> documentTypes,
    required bool? isScreenshot,
    required List<int> starts,
    required List<int?> ends,
  }) {
    int? dateFrom;
    int? dateTo;
    if (starts.isNotEmpty) {
      dateFrom = starts.reduce((a, b) => a < b ? a : b);
      final boundedEnds = ends.whereType<int>().toList(growable: false);
      if (boundedEnds.isNotEmpty) {
        final earliestEnd = boundedEnds.reduce((a, b) => a < b ? a : b);
        if (earliestEnd >= dateFrom) dateTo = earliestEnd;
      }
    }
    return QueryInterpretation(
      keywords: keywords,
      categories: categories,
      isScreenshot: isScreenshot,
      documentTypes: documentTypes,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }

  static int _startOfToday(int? nowEpochSeconds) {
    if (nowEpochSeconds == null) return -1;
    final now = DateTime.fromMillisecondsSinceEpoch(nowEpochSeconds * 1000)
        .toLocal();
    final start = DateTime(now.year, now.month, now.day);
    return start.millisecondsSinceEpoch ~/ 1000;
  }

  static int _startOfWeek(int? nowEpochSeconds) {
    if (nowEpochSeconds == null) return -1;
    final now = DateTime.fromMillisecondsSinceEpoch(nowEpochSeconds * 1000)
        .toLocal();
    final startOfToday = DateTime(now.year, now.month, now.day);
    // ISO weeks start on Monday; Dart's weekday is 1=Monday … 7=Sunday.
    final monday = startOfToday.subtract(Duration(days: now.weekday - 1));
    return monday.millisecondsSinceEpoch ~/ 1000;
  }

  static int _startOfMonth(int? nowEpochSeconds) {
    if (nowEpochSeconds == null) return -1;
    final now = DateTime.fromMillisecondsSinceEpoch(nowEpochSeconds * 1000)
        .toLocal();
    final start = DateTime(now.year, now.month, 1);
    return start.millisecondsSinceEpoch ~/ 1000;
  }

  static void _addUnique(List<ContentCategory> target, ContentCategory value) {
    if (!target.contains(value)) target.add(value);
  }
}
