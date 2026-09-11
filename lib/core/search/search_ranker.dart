import '../database/app_database.dart';
import '../platform/content_access_models.dart' show ContentCategory;
import 'search_field.dart';
import 'search_normalizer.dart';
import 'search_query.dart';
import 'search_result.dart';

/// One candidate row entering the ranker: the persisted row plus any
/// recognition text the retrieval stage found for it (nullable when the row
/// was retrieved from metadata only, or has no OCR content yet).
class SearchCandidate {
  const SearchCandidate({required this.item, this.ocrText});

  final MediaItem item;

  /// Normalized OCR text (`ocr_content.normalized_text`), when this candidate
  /// came from OCR retrieval and was still current.
  final String? ocrText;
}

/// Result of scoring one candidate (row + optional OCR text) against query
/// tokens.
class ScoredMatch {
  const ScoredMatch({required this.score, required this.matches});

  final int score;

  /// One entry per matched (field, token) pair — the input for the future
  /// "why this matches" line.
  final List<MatchInfo> matches;
}

/// Deterministic, field-weighted keyword scoring (docs `search.md` §Ranking).
///
/// Pure logic with no I/O so ranking is trivial to unit-test and easy to
/// replace wholesale when OCR/semantic retrieval land (their scoring will sit
/// behind [SearchRanker], not inside it).
class SearchScorer {
  const SearchScorer();

  /// Base weight per field. Why each value exists:
  ///
  /// * `displayName` (> `title`) — the filename is the primary identity users
  ///   remember; "citizenship_front.jpg" should beat a path-only mention.
  /// * `title` — MediaStore titles are usually equal to or richer than the
  ///   name, but not universally present, so slightly below displayName.
  /// * `ocrText` (between title and folder) — body text is a *content* signal:
  ///   stronger than a folder mention, but an exact filename or title still
  ///   wins. An exact OCR phrase surfaces (weight dominates a filename
  ///   substring), while a generic OCR substring never outranks a clear name.
  /// * `relativePath` / `bucketDisplayName` — useful context, deliberately
  ///   weak: a token in a path should never outrank a filename substring.
  /// * `artist`/`album`/`albumArtist`/`genre` — music metadata, lowest tier.
  static const Map<SearchField, int> fieldWeight = {
    SearchField.displayName: 50,
    SearchField.title: 44,
    SearchField.ocrText: 20,
    SearchField.relativePath: 12,
    SearchField.bucketDisplayName: 12,
    SearchField.artist: 8,
    SearchField.album: 8,
    SearchField.albumArtist: 8,
    SearchField.genre: 8,
  };

  /// Multiplier per match strength: an exact whole-word match outweighs a
  /// prefix, which outweighs a plain substring. This is what makes
  /// `citizenship` rank `citizenship_front.jpg` above a mere substring hit.
  static const Map<MatchStrength, int> strengthFactor = {
    MatchStrength.exact: 3,
    MatchStrength.prefix: 2,
    MatchStrength.substring: 1,
  };

  /// Bonus per *additional* distinct matched token, so a row matching
  /// 3/3 query tokens always scores above one matching 1/3 when field hits are
  /// otherwise comparable.
  static const int coverageBonus = 25;

  ScoredMatch score({
    required String displayName,
    String? title,
    String? relativePath,
    String? bucketDisplayName,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    String? ocrText,
    required List<String> tokens,
  }) {
    final fields = <SearchField, String?>{
      SearchField.displayName: displayName,
      SearchField.title: title,
      SearchField.relativePath: relativePath,
      SearchField.bucketDisplayName: bucketDisplayName,
      SearchField.artist: artist,
      SearchField.album: album,
      SearchField.albumArtist: albumArtist,
      SearchField.genre: genre,
      SearchField.ocrText: ocrText,
    };

    var base = 0;
    final matches = <MatchInfo>[];
    final matchedTokens = <String>{};

    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null || value.isEmpty || tokens.isEmpty) continue;
      final words = SearchNormalizer.words(value);
      if (words.isEmpty) continue;

      for (final token in tokens) {
        final strength = _bestStrength(words, token);
        if (strength == null) continue;
        base += fieldWeight[entry.key]! * strengthFactor[strength]!;
        matchedTokens.add(token);
        matches.add(
          MatchInfo(field: entry.key, token: token, strength: strength),
        );
      }
    }

    final bonus = matchedTokens.length > 1
        ? coverageBonus * (matchedTokens.length - 1)
        : 0;
    return ScoredMatch(score: base + bonus, matches: matches);
  }

  /// Best strength across the field's normalized words, or null when the token
  /// does not appear at all.
  static MatchStrength? _bestStrength(List<String> words, String token) {
    MatchStrength? best;
    for (final word in words) {
      final strength = _strengthOf(word, token);
      if (strength == null) continue;
      if (best == null || strength.index < best.index) best = strength;
    }
    return best;
  }

  static MatchStrength? _strengthOf(String word, String token) {
    if (word == token) return MatchStrength.exact;
    if (word.startsWith(token)) return MatchStrength.prefix;
    if (word.contains(token)) return MatchStrength.substring;
    return null;
  }
}

/// Ranks raw candidate rows into settled [SearchResult]s.
class SearchRanker {
  const SearchRanker({this.scorer = const SearchScorer()});

  final SearchScorer scorer;

  /// Scores every candidate, sorts deterministically
  /// (`score desc → dateModified desc → stableKey asc`) and returns at most
  /// [limit] results. Empty [NormalizedSearchQuery.tokens] produces filter-only
  /// results scored 0 (recency order).
  List<SearchResult> rank(
    List<SearchCandidate> candidates,
    NormalizedSearchQuery query,
  ) {
    final results = candidates
        .map((candidate) {
          final row = candidate.item;
          final scored = scorer.score(
            displayName: row.displayName,
            title: row.title,
            relativePath: row.relativePath,
            bucketDisplayName: row.bucketDisplayName,
            artist: row.artist,
            album: row.album,
            albumArtist: row.albumArtist,
            genre: row.genre,
            ocrText: candidate.ocrText,
            tokens: query.tokens,
          );
          return SearchResult(
            stableKey: row.stableKey,
            contentUri: row.contentUri,
            displayName: row.displayName,
            category: _categoryOf(row.category),
            volumeName: row.volumeName,
            mediaStoreId: row.mediaStoreId,
            title: row.title,
            mimeType: row.mimeType,
            sizeBytes: row.sizeBytes,
            dateModified: row.dateModified,
            relativePath: row.relativePath,
            width: row.width,
            height: row.height,
            durationMs: row.durationMs,
            isScreenshot: row.isScreenshot,
            score: scored.score,
            matches: scored.matches,
          );
        })
        .toList(growable: false);

    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byDate = _epochSeconds(b.dateModified)
          .compareTo(_epochSeconds(a.dateModified));
      if (byDate != 0) return byDate;
      return a.stableKey.compareTo(b.stableKey);
    });

    return results.length > query.limit
        ? results.sublist(0, query.limit)
        : results;
  }

  static int _epochSeconds(int? value) => value ?? -1;

  static ContentCategory _categoryOf(String wire) =>
      ContentCategory.fromWire(wire);
}
