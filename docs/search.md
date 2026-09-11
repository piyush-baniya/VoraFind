# VoraFind — Local Metadata Search

Status: **Implemented (Prompt #7) — keyword + metadata search over the local
index with deterministic ranking, explainable match context, and a live
debounced search UI. Prompt #8 extends the projection with on-device OCR
body text (`ocr_content`, see `docs/ocr.md`): metadata and OCR retrieval run
in parallel, merge and deduplicate by stable key, and OCR hits are explained as
"Matched in OCR text".**

Last updated: 2026-09-11

---

## 1. Purpose

Search is the product's core interaction. The search box is the primary UI
(AGENTS.md §17). The MVP promise is: *find anything you've saved on your phone*
by matching what VoraFind already knows about a file — its name, path, folder,
album, artist, genre, and MediaStore metadata — **entirely on device, offline,
without rescans**.

This document covers:

- what is searchable today (the retrieval projection),
- how queries are normalized, interpreted, matched, and ranked,
- why a single normalized column was chosen over FTS,
- performance/limits guarantees,
- what is explicitly out of scope.

## 2. Searchable Surface

All retrieval reads the `media_items.searchable_text` projection (schema v3,
`docs/persistence.md` §3). One row keeps the input to the normalizer; the
projection is derived, **not** recomputed on read:

| Source `MediaItem` field | Included in `searchable_text` |
|---|---|
| `display_name` | yes |
| `title` | yes |
| `relative_path` | yes |
| `bucket_display_name` | yes |
| `artist` | yes |
| `album` | yes |

A second, **parallel** retrieval path reads `ocr_content.normalized_text`
(Prompt #8): the body text ML Kit extracted from the image itself (`.jpg`,
`.png`, `.webp`, `.bmp`, `.gif`). Its results are merged with metadata results
and deduplicated by stable key (§3.4). Both paths use the same normalizer, so a
user's typing and the indexed text always agree.

Not included (future): captions, audio transcripts, PDF/Word text, image
features. Such content would add columns, not change the architecture.

### Filters (metadata, not text)

Independent of keywords, a query can carry:

- `categories` — `images`, `videos`, `audio`, `documents` (from `ContentCategory.name`).
- `isScreenshot` — the screenshot-first UX.
- `dateModified` range, `sizeBytes` range, `durationMs` range (inclusive bounds).
- `pathPrefix` — exact folder-prefix match on `relative_path`, with LIKE
  wildcards treated as literals (the normalizer strips them; the prefix
  predicate additionally escapes `\`, `%`, `_`).

## 3. Pipeline

```
query text ──▶ normalize ──▶ interpret ──▶ SearchQuery
                                               │
   MediaItem.searchableText ── raw row pool (SQL, bounded) ─┐
   ocr_content.normalizedText ── OCR row pool (SQL, bounded)┤ parallel
                                                             │
                        rank (Dart) ◀──── merge by stableKey ┘
                                     ──▶ SearchResult[limit]
```

### 3.1 Normalization

`SearchNormalizer.canonical`:

- lowercase (ASCII),
- split on any non-alphanumeric separator, collapsing runs,
- drop separators entirely (so a literal `%` in a file name cannot become a
  LIKE wildcard),
- keep only ASCII word characters; token kernel is `[a-z0-9]`.

`tokens` = the resulting non-empty pieces. `storageText` joins the fields above
through the same folding so that a user's typing and the indexed text always
agree. This makes substring containment (SQL `LIKE '%token%'`) sound: the
wildcard characters that would otherwise make `LIKE` unsafe never exist in the
indexed text or the query.

### 3.2 Interpretation

`SearchQueryInterpreter` turns media words into filters and keeps everything else
as keywords (AGENTS.md §14/§17 — no hidden magic):

| input word | effect |
|---|---|
| `screenshot`, `screenshots`, `ss` | `isScreenshot = true`, dropped from keywords |
| `image`, `images`, `photo`, `photos`, `picture`, `pictures` | `categories += images`, dropped |
| `video`, `videos` | `categories += videos`, dropped |
| `audio`, `song`, `songs`, `music`, `mp3` | `categories += audio`, dropped |
| `document`, `documents`, `doc`, `docs` | `categories += documents`, dropped |
| `pdf`, `pdfs` | `documentTypes += pdf` (Prompt #10), dropped |
| `text`, `txt` | `documentTypes += text`, dropped |
| `markdown`, `md` | `documentTypes += markdown`, dropped |
| `today` / `yesterday` | `dateFrom`/`dateTo` pinned to the local day (needs a clock) |
| `this week` / `this month` | `dateFrom` pinned to Monday / the 1st (phrase required; bare `week`/`month` stay keywords) |
| `recent`, `recently` | `dateFrom` = start of today − 6 days |

Time words are resolved against an injectable clock (`SearchService.nowSeconds`);
without a clock they stay keywords, so interpretation stays deterministic and
testable. A pinned document type excludes MediaStore rows entirely — "find
pdfs" consults only the document index. Screenshot queries drop document-type
pins (documents never match a screenshot query).

Explicit fields on the query (`categories`, `isScreenshot`, `dateFrom`,
`documentTypes`) **override**
interpretation. Unknown words stay keywords. Filters combine with `AND`;
keywords combine with `OR`, coverage-ranked.

### 3.3 Retrieval (bounded, indexed)

`DriftMediaRepository.searchCandidates` runs one SQL statement, never a
full-library scan:

- `WHERE` = conjunction of: generic `true`, category `IN` filter, `is_screenshot`
  filter, ranges, path-prefix `LIKE`, and keyword predicate = OR of
  `searchable_text LIKE '%token%'` per token.
- `ORDER BY` a computed coverage expression first (`instr(searchable_text, token) > 0`
  summed per alphanumeric token — `token`s are validated alphanumeric at parse
  time, so the literal is injection-safe), then `date_modified DESC`,
  `stable_key ASC` for determinism.
- **Pool bound** (AGENTS.md §12, §14 — never scan the whole library): keyword
  queries fetch `min(limit × 4, 400)` rows; filter-only queries fetch exactly
  `limit` (no ranking needed, direct recency order).
- The `(category, date_modified)` index serves the common "filter then recency"
  shapes; keyword filtering is capped so a full `searchable_text` scan of the
  **pool** only ever reads a few thousand rows at most.
- **OCR path (`searchOcrCandidates`, Prompt #8).** Runs in parallel and
  consults only `completed` rows: keyword predicate = OR of
  `instr(normalized_text, token) > 0`, `ORDER BY` a computed coverage
  expression (omitted entirely when the query has no alphanumeric tokens —
  SQLite treats `ORDER BY (0)` as a column index), then `stable_key ASC` for
  determinism. Pool bound mirrors metadata (`min(limit × 4, 400)`), pages via
  the `(status, stable_key)` index. Empty queries skip OCR entirely (no
  expensive scan for a blank box).

### 3.4 Ranking

`SearchScorer` scores a candidate row against the query tokens. Ranking signals
and why they exist:

| signal | weight | rationale |
|---|---|---|
| `display_name` match | 50 | the file name is what users most often half-remember |
| `title` match | 44 | second most-memorized metadata (nominal for audio) |
| `ocrText` match | 20 | body text proves *content* relevance — stronger than folder, weaker than remembered name/title |
| `relative_path` / `bucket_display_name` | 12 | folder context ("I saved it in X") |
| `artist` / `album` | 8 | audio identity when title is missed |

Within a matched field, strength rankers: **exact word** (3) > **prefix** (2) >
**substring** (1). A `coverage` bonus of `25 × (matchedTokens − 1)` rewards
queries that hit more of their terms. Sorting: score descending, then
`date_modified` descending, then `stable_key` ascending — deterministic and
testable (AGENTS.md §14).

Scores are internal only. The UI shows *why* a row matched
(`MatchInfo{field, token, strength}` → "Matched in name: aadhaar, card")
instead of a meaningless relevance number (AGENTS.md §17).

### 3.5 Service & state

`SearchService` validates/bounds the query (negative or inverted ranges →
`SearchException.invalidQuery`; limit clamped to `[1, 200]`, default 50) and maps
repository failures to `SearchException.database`. Empty queries short-circuit to
zero results with no database touch. When a keyword query has content, metadata
and OCR retrieval run concurrently (`(…) .wait`, §3.3); `_merge` deduplicates by
stable key, keeping the metadata row when both pools hit it and attaching its
OCR text so body matches still score. A filter-only query skips the OCR path
(OCR adds no filtering dimension in this phase).

`searchResultsProvider` (`SearchResultsNotifier`) holds the async state
(`idle | loading | data | error`) and guards with a **generation counter +**
`ref.mounted`, so a stale debounced request can never overwrite a newer one. The
screen debounces keystrokes (250 ms) and cancels in-flight work implicitly via the
generation guard.

## 4. Why a single column instead of FTS5

FTS5 (or a token table) is the standard bulletproof answer for text search, and
the AGENTS.md guidance is to reconsider external indexing when it demonstrably
wins. Today it does not (this now includes OCR text):

- Searchable volume is **metadata + OCR text of personal libraries**. Even a
  dense 10 k-file library is ~10–20 MB of text and tens of "rows touching a
  token." A bounded `LIKE '%t%'` scan over the pool (≤ `min(limit × 4, 400)`
  rows per path) is a handful of milliseconds on SQLite.
- FTS5 requires either a **shadow-table index** (extra writes on every upsert,
  trigger/DRT maintenance) or **runtime external-content queries** (planning
  complexity) — both add moving parts for no measured gain at this scale.
- FTS5 default ranking (BM25) is great for document corpora; VoraFind's ranking
  is metadata-field-aware (name > title > OCR text > folder > artist), which a
  single-column FTS row cannot express without custom scoring hacks.

The projection is deliberately keyed to the same normalized form the query uses,
so the seam can later swap to FTS5/trigram/Roaring-bitmap per-token indexes
*without changing the ranking layer*.

## 5. Performance & limits contract

- **100 ms-class search** on a mid-range phone against a library-sized index
  (smoke benchmark: 5000 rows ≪ 10 s budget; see
  `test/search/search_performance_test.dart`).
- No operation scans the whole library for a normal search.
- Candidate pool bounded (above); result list bounded by `limit`.
- Search blocks nothing: debounced, async, on drift's executor — no UI thread
  work.

## 6. Testing

- **Unit**: normalizer, interpreter, ranker, service (validation + error
  mapping), metadata+OCR merge by stable key; Prompt #10 adds document-word
  and time-word interpretation (`test/search/search_interpreter_document_date_test.dart`)
  including the no-clock keyword fallback and document-type/date merging.
- **DB**: migration v2→v3 backfill fidelity; `searchCandidates` SQL behavior
  (keyword OR, coverage ordering, filters, prefix escaping, pool bound,
  rollback visibility, no-matches); `searchOcrCandidates` (completed-only,
  empty-token safety, current rows win over stale lines, pool bound).
- **Integration**: 5000-row smoke benchmark through SQL + Dart ranking.
- **Widget**: search screen states (idle, loading, no-results), dark theme,
  branding.

## 7. Privacy

Everything matches on-device metadata. No content leaves the device, no network,
no analytics. Errors (`SearchException`) never embed user file names, paths, or
content.

## 8. Out of scope (deferred, do not implement)

PDF/Word text extraction, audio transcripts, image similarity/embeddings,
semantic/vector search, cross-device search, and AI chat. OCR body text (Prompt
#8) is implemented and lives behind the same projection + ranking layers
(weight 20); deterministic metadata search stays available and unchanged
(AGENTS.md §15). When semantics eventually arrive they extend the same seam.