import '../database/app_database.dart';
import '../platform/content_access_models.dart' show ContentCategory;
import '../semantic/semantic_models.dart' show SemanticDefaults;
import '../visual/visual_models.dart' show VisualDefaults;
import 'search_field.dart';
import 'search_normalizer.dart';
import 'search_query.dart';
import 'search_result.dart';

/// One candidate row entering the ranker: the persisted row (media item or
/// document) plus any recognition/extracted text the retrieval stage found for it.
class SearchCandidate {
  const SearchCandidate({
    this.item,
    this.document,
    this.ocrText,
    this.documentText,
    this.semanticKey,
    this.semanticSimilarity,
    this.visualConcept,
    this.visualConfidence,
    this.visualFrameTsMs,
  }) : assert(
         item != null || document != null || semanticKey != null,
         "Candidate must provide an item, a document, or a semantic key",
       );

  final MediaItem? item;
  final Document? document;

  /// Stable key for a semantic-only candidate (no local row yet). When set,
  /// [item] and [document] are null and the ranker treats this as a semantic
  /// match whose row is resolved from the existing media/document pool.
  final String? semanticKey;

  /// Normalized OCR text (`ocr_content.normalized_text`), when this candidate
  /// came from OCR retrieval and was still current.
  final String? ocrText;

  /// Normalized document text (`document_content.normalized_text`), when this
  /// candidate came from document text retrieval.
  final String? documentText;

  /// Cosine similarity of the stored embedding against the query embedding,
  /// when this candidate came from semantic retrieval. `null` for keyword-only
  /// candidates. Always paired with a [SearchField.semantic] match in
  /// [SearchResult.matches] by the ranker.
  final double? semanticSimilarity;

  /// Best visual concept match for a video candidate: the stored concept name
  /// (e.g. `beach`) plus its confidence and the best frame timestamp.
  final String? visualConcept;
  final double? visualConfidence;
  final int? visualFrameTsMs;
}

/// Result of scoring one candidate (row + optional OCR/document text) against
/// query tokens.
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
  /// * `documentText` / `ocrText` (between title and folder) — body text is a
  ///   *content* signal: stronger than a folder mention, but an exact filename
  ///   or title still wins.
  /// * `relativePath` / `bucketDisplayName` — useful context, deliberately
  ///   weak: a token in a path should never outrank a filename substring.
  /// * `artist`/`album`/`albumArtist`/`genre` — music metadata, lowest tier.
  static const Map<SearchField, int> fieldWeight = {
    SearchField.displayName: 50,
    SearchField.title: 44,
    SearchField.documentText: 22,
    SearchField.ocrText: 20,
    SearchField.relativePath: 12,
    SearchField.bucketDisplayName: 12,
    SearchField.artist: 8,
    SearchField.album: 8,
    SearchField.albumArtist: 8,
    SearchField.genre: 8,
  };

  /// Rank points a perfect semantic match contributes. Deliberately above the
  /// weakest keyword hits (path/genre) so a real semantic match rescues rows
  /// keyword search misses, yet still below every exact filename/title/OCR/doc
  /// hit so a precise keyword signal always keeps priority. Single source of
  /// truth: [SemanticDefaults.semanticRankWeight] (Prompt #14 measured the
  /// model's relevant/unrelated similarity gap before choosing the value).
  static const int semanticRankWeight = SemanticDefaults.semanticRankWeight;

  /// Rank points a confidence-1.0 visual match contributes. Deliberately below
  /// an exact filename/title/OCR/doc hit and below a strong semantic match so
  /// keyword correctness keeps priority. Single source of truth:
  /// [VisualDefaults.visualRankWeight].
  static const int visualRankWeight = VisualDefaults.visualRankWeight;

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
    String? documentText,
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
      SearchField.documentText: documentText,
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

  /// Scores a purely semantic hit: `similarity` in [0, 1] maps linearly to
  /// [0, semanticRankWeight]. Returns a single [SearchField.semantic] match so
  /// the result can explain *why* it surfaced. No keyword tokens are consumed —
  /// semantic and keyword scores are additive in [SearchRanker].
  ScoredMatch scoreSemantic(double similarity) {
    final clamped = similarity.clamp(0.0, 1.0);
    final points = (clamped * semanticRankWeight).round();
    return ScoredMatch(
      score: points,
      matches: [
        MatchInfo(
          field: SearchField.semantic,
          token: '',
          strength: MatchStrength.substring,
        ),
      ],
    );
  }

  /// Scores a visual hit: `confidence` in [0, 1] maps linearly to
  /// [0, visualRankWeight]. Returns a single [SearchField.visual] match whose
  /// token is the stored concept name so the UI can render "Visual match".
  /// Additive with keyword/semantic scores in [SearchRanker]; kept below any
  /// exact filename/title/OCR/doc hit per [VisualDefaults.visualRankWeight].
  ScoredMatch scoreVisual({
    required String concept,
    required double confidence,
  }) {
    final clamped = confidence.clamp(0.0, 1.0);
    final points = (clamped * visualRankWeight).round();
    return ScoredMatch(
      score: points,
      matches: [
        MatchInfo(
          field: SearchField.visual,
          token: concept,
          strength: MatchStrength.substring,
        ),
      ],
    );
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
  ///
  /// `matches` are ordered keyword-first, semantic-last so the first listed
  /// signal is always the most specific one ("Matched in name: resume" tells
  /// the user more than "semantic match"); a candidate with neither a media row
  /// nor a document row is dropped defensively (it cannot produce a result).
  List<SearchResult> rank(
    List<SearchCandidate> candidates,
    NormalizedSearchQuery query,
  ) {
    final results = candidates
        .where(
          (candidate) => candidate.item != null || candidate.document != null,
        )
        .map((candidate) {
          // Keyword exact/weighted scoring always runs first; a semantic
          // similarity contributes additively on top. A perfect semantic match
          // stays below an exact single-token filename hit, so keyword
          // precision outranks fuzzy semantic recall, while a strong semantic
          // match (>0.4) still outranks the weakest metadata substring hits
          // (AGENTS.md §6 product priorities: correctness > recall).
          final matches = <MatchInfo>[];
          int keywordScore = 0;

          if (candidate.document != null) {
            final doc = candidate.document!;
            final scored = scorer.score(
              displayName: doc.displayName,
              relativePath: doc.relativePath,
              documentText: candidate.documentText,
              tokens: query.tokens,
            );
            keywordScore = scored.score;
            matches.addAll(scored.matches);
          } else {
            final row = candidate.item!;
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
            keywordScore = scored.score;
            matches.addAll(scored.matches);
          }

          // Semantic retrieval enforces `SemanticDefaults.minSimilarity`
          // before any candidate reaches the pool; the ranker mirrors the
          // check so a sub-threshold similarity can never fabricate a
          // "semantic match" on a weak coincidence (defense-in-depth).
          final similarity = candidate.semanticSimilarity;
          final semanticScored =
              similarity != null && similarity >= SemanticDefaults.minSimilarity
              ? scorer.scoreSemantic(similarity)
              : null;
          if (semanticScored != null) {
            matches.addAll(semanticScored.matches);
          }
          // Visual retrieval enforces `VisualDefaults.minConceptConfidence`
          // before any candidate reaches the pool; the ranker mirrors the
          // check so a sub-threshold confidence can never fabricate a
          // "visual match" (defense-in-depth). Media-only: documents never
          // carry visual signals.
          final visualConcept = candidate.visualConcept;
          final visualConfidence = candidate.visualConfidence;
          final visualScored =
              candidate.document == null &&
                  visualConcept != null &&
                  visualConcept.isNotEmpty &&
                  visualConfidence != null &&
                  visualConfidence >= VisualDefaults.minConceptConfidence
              ? scorer.scoreVisual(
                  concept: visualConcept,
                  confidence: visualConfidence,
                )
              : null;
          if (visualScored != null) {
            matches.addAll(visualScored.matches);
          }
          final score =
              keywordScore +
              (semanticScored?.score ?? 0) +
              (visualScored?.score ?? 0);

          if (candidate.document != null) {
            final doc = candidate.document!;
            return SearchResult(
              stableKey: doc.stableKey,
              contentUri: doc.uri,
              displayName: doc.displayName,
              category: ContentCategory.documents,
              volumeName: null,
              mediaStoreId: null,
              title: null,
              mimeType: doc.mimeType,
              sizeBytes: doc.sizeBytes,
              dateModified: doc.dateModified,
              relativePath: doc.relativePath,
              width: null,
              height: null,
              durationMs: null,
              isScreenshot: false,
              score: score,
              matches: matches,
            );
          }
          final row = candidate.item!;
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
            score: score,
            matches: matches,
            visualConcept: candidate.visualConcept,
            visualFrameTsMs: candidate.visualFrameTsMs,
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
