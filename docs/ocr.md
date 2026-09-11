# VoraFind — Local On-Device OCR Pipeline

Status: **Implemented (Prompt #8) — a fully local, resumable, cancellable OCR
pipeline that extracts text from the phone's own images with Google ML Kit
`text-recognition` (bundled model, ~20 MB APK cost), persists per-file durable
outcomes in `ocr_content` (schema v4), and merges body-text matches into search
alongside metadata ("Matched in OCR text"). No file bytes, OCR text, or
derived data ever leave the device.**

Last updated: 2026-09-11

---

## 1. Purpose

VoraFind's promise is *find anything you've saved on your phone*. Filenames and
folder metadata cannot find the content *inside* an image — a receipt, a card,
a note. On-device OCR gives the search engine a body-text signal while keeping
a hard privacy boundary (AGENTS.md §8, §15).

Scope discipline (AGENTS.md §27):

- **In scope:** raster images the user already granted via media permissions
  (`image/jpeg`, `image/png`, `image/webp`, `image/bmp`, `image/gif`).
- **Out of scope (deliberately, do not implement):** PDF/document/video/audio
  text extraction, HEIF, embeddings/semantic search, cloud or external OCR
  APIs, analytics of extracted content, any network transfer.

## 2. Architecture

```
┌─ Dart (lib/core/ocr) ─────────────────────────────────────────────────┐
│ OcrCoordinator        start/cancel, batch drain, progress stream,     │
│                       per-row failure isolation, durable status       │
│ OcrDetector (iface) ── MethodChannelOcrDetector (channel vorafind/ocr)│
├─ Kotlin (android …/ocr) ──────────────────────────────────────────────┤
│ OcrBridge (MethodChannel) → OcrService (single-thread, busy guard)    │
│   → OcrBitmapLoader (typeof-BitmapFactory decode + EXIF rotation)     │
│   → ImageSampler (power-of-two downsampling, max 2048px)              │
│   → ML Kit TextRecognition(latin) ── create /close per call           │
└────────────────────────────────────────────────────────────────────────┘
```

- Kotlin is a **stateless recognizer**: it never opens the database and never
  decides what to keep (AGENTS.md §7). Dart owns the queue, state, and
  persistence.
- Discovery (metadata) and OCR are decoupled (architecture doc §16): OCR never
  blocks discovery and vice-versa; a fresh scan only marks rows that changed.

## 3. The pipeline

Driven by `OcrCoordinator.start()` (lib/core/ocr/ocr_coordinator.dart):

1. **Eligibility.** `MediaRepository.ocrStats().eligible` = rows in
   `media_items` whose `mime_type` is image/*, independent of access scope.
2. **Drain.** `findOcrCandidates(batchSize, nowEpochSeconds)` pages the pending
   queue (SQL, bounded — never a full-library scan):
   - status is `pending` (never OCR'd),
   - `metadata_revision > source_revision` (the file's metadata changed since
     its last extraction),
   - **or** status is `failed` and the last attempt is older than the
     `COOLDOWN_SECONDS` backoff window.
   - `unsupported` rows are filtered out permanently; `completed` rows are
     re-OCR'd only when `metadata_revision` moves (invalidation, §6).
3. **Recognize.** Each candidate goes to the native detector with
   `maxImageDimension = 2048` (a decode-dimension cap, indices §4).
4. **Persist.** `saveOcrResult` upserts the outcome (indexed by stable key) with
   the candidate's `metadata_revision` as `source_revision` — the invalidation
   anchor.
5. **Progress.** A single `Stream<OcrRunProgress>` broadcasts at batch
   granularity (running / completed / cancelled / failed) so the UI shows one
   calm line, not a live counter per image.

Runs are single-flight: a second `start()` while one is active returns
`running` and does **not** queue a second run (lifecycle resumes cannot pile up
re-runs). Cancellation is cooperative, checked between candidates; an
interrupted run reports `cancelled` and everything it persisted is durable.

Battery (AGENTS.md §22): runs begin on app resume and are cancelled on pause;
each batch is cheap; no background worker, no periodic drain.

## 4. Native recognizer (Kotlin)

Files: `android/app/src/main/kotlin/com/piyushbaniya/vorafind/ocr/`.

- **`ImageSampler.kt`** — pure, unit-tested. `inSampleSizeFor(w, h)` returns the
  smallest power of two such that both decoded dimensions are ≤ the cap after
  sampling (`ceil(w/sample) ≤ max` **and** `ceil(h/sample) ≤ max`; exact-fit
  grids give sample 1). This bounds decode memory without distorting the image.
- **`OcrBitmapLoader.kt`** — decodes bounds-only first, then `inSampleSize`,
  then rotates for EXIF orientation (`androidx.exifinterface`, handles
  flip/transpose). `minSdk 24` rules out `ImageDecoder` (API 28+); the
  BitmapFactory path is deliberately un-fancy and leak-free (`recycle()` in a
  `finally`).
- **`OcrService.kt`** — a single-thread daemon executor; an `AtomicBoolean`
  single-flight guard rejects a second call with `busy` while one is in flight;
  ML Kit instances are created and closed **per call** to avoid leaked
  recognizers; decoding/recognition failures surface as typed errors.
- **`OcrBridge.kt`** — `MethodChannel "vorafind/ocr"`, registered in
  `MainActivity`. Wire contract (§7). Errors and outcomes are small and typed so
  the Flutter side maps them 1:1.

### 4.1 ML Kit dependency facts (verified 2026-09)

- `com.google.mlkit:text-recognition:16.0.1` — **bundled** model, adds ~20 MB
  to the APK; no download at runtime, so OCR works offline and persists (in
  exchange for the size). This trade-off is explicit: VoraFind's core promise
  depends on offline search.
- The concrete options type is
  `com.google.mlkit.vision.text.latin.TextRecognizerOptions.DEFAULT_OPTIONS`
  (Latin script). There is **no** `com.google.mlkit.vision.text.TextRecognizerOptions`;
  `TextRecognition.getClient(TextRecognizerOptionsInterface)` is the only entry.
- Transitive artifacts: `play-services-mlkit-text-recognition(-common)`,
  `text-recognition-bundled-common`, `vision-common`.
- No new Android permissions are required for OCR.

## 5. Durable outcomes, status & errors

`OcrStatus` (lib/core/ocr/ocr_models.dart) is stored per row in
`ocr_content.status`:

| status | meaning | retried? |
|---|---|---|
| `pending` | never attempted yet | default queue membership |
| `completed` | recognized; `raw_text`/`normalized_text` live here | only when `metadata_revision` changes (§6) |
| `failed` | transient failure (URI gone/revoked, recognizer hiccup, busy) | after `COOLDOWN_SECONDS` (default 1 h) |
| `unsupported` | proven-unopenable/undecodable bytes, or decode failure | no (durable) |

Per-row failures never fail the run (AGENTS.md §13, §19): one corrupt image
cannot stop the pipeline. Failure isolation mapping:

| wire `errorCode` | derived status |
|---|---|
| `decodeFailed` | `unsupported` (proven permanent) |
| `uriUnavailable`, `ocrFailed`, `busy`, `invalidArguments` | `failed` (transient, cooldown) |
| `platformUnavailable`, `unknown` | `failed` (transient) |

`error_code` stores the wire name for transparency and testability; messages are
never user-content (AGENTS.md §19) — filenames/OCR text are never put in errors.

## 6. Invalidation

Derived data needs an invalidation path (AGENTS.md §20). For OCR text that path
is **`metadata_revision`**:

- Every extraction stores the source row's `metadata_revision` as
  `source_revision`.
- A row re-enters the pending queue when its current `metadata_revision`
  exceeds `source_revision` (re-discovery of the same file changed something).
- `raw_text` is the recognizer's output verbatim; `normalized_text` is the
  same normalizer used for metadata search, so query and index always agree.
- Deleting a `media_items` row cascades to its `ocr_content` row
  (`ON DELETE CASCADE`); `clearAll` drops OCR content with it.

## 7. Wire contract (Dart ⇄ Kotlin)

Channel `vorafind/ocr` — `MethodChannel`, command `recognizeText`:

| in | out (success) | out (failure) |
|---|---|---|
| `contentUri: String`, `maxWidth: Int?` | `{text: String?, errorCode: String?, errorMessage: String?}` | `error(code, message, null)` |

- Success is a map (never a bare string) so the contract extends to structured
  errors without a version bump.
- Error codes: `invalidArguments | busy | uriUnavailable | decodeFailed |
  ocrFailed`. `OcrErrorCode.fromWire` and the Kotlin `OcrError` constants are
  asserted to stay in sync by `OcrWireContractTest` (JVM) and
  `test/ocr/ocr_coordinator_test.dart` (Dart).
- No file bytes ever cross the channel — only the content URI.

## 8. Search integration

`SearchService` runs metadata and OCR retrieval **in parallel** and merges the
two bounded pools (see docs/search.md §3.4). A row hit by both keeps its
metadata occurrence and gains its OCR text, so body matches are scored.
Ranking: `SearchField.ocrText` (weight 20) sits between `title` (44) and the
folder signals (12) — a body-text hit outranks a folder hit but not a name hit
(the ranking table and rationale live in docs/search.md). The UI explains the
hit as `Matched in OCR text` (AGENTS.md §17) instead of a score.

## 9. Performance

- Every DB operation is bounded: `ocrStats` is a count; `findOcrCandidates`
  pages `batchSize` (default 10) rows via `ORDER BY status sort, stable_key`
  and the `(status, stable_key)` covering index; the OCR keyword predicate is an
  OR of `instr(normalized_text, token) > 0` with a pool bound of
  `min(limit × 4, 400)`.
- Decodes happen on the Kotlin single executor, never the UI thread. Dart
  orchestrates with `await`s — no jank from synchronous work (AGENTS.md §31).
- Empty-token searches omit the coverage ordering term entirely (SQLite treats
  `ORDER BY (0)` as a column index, which would error).

## 10. Privacy

- ML Kit `text-recognition` runs fully on device with the bundled model. No
  network, no server, no analytics of extracted content.
- OCR text lives in app-private SQLite (`ocr_content`), never in logs or error
  messages, and is searchable only inside the app.
- No new permissions were added for OCR.

## 11. Testing

- **JVM:** `ImageSamplerTest` (sampling math incl. exact-fit 2048@2048 → 1) and
  `OcrWireContractTest` (channel name, method name, code-name parity with Dart).
- **Dart unit:** `test/database/ocr_repository_test.dart` (eligibility, paging,
  cooldown, revision invalidation, `unsupported` permanence, upsert
  idempotence, `ocrStats`, OCR search correctness, cascade delete) and
  `test/ocr/ocr_coordinator_test.dart` (drain, failure isolation, cancellation,
  single-flight, progress stream).
- **Search:** metadata+OCR merge and ranking are covered by the search tests.
- Real ML Kit recognition still needs a device/emulator smoke test — unit and
  JVM tests cover the contract but not the bundled model's pixel output.

## 12. Out of scope (deferred, do not implement)

PDF/Word document OCR, video/audio transcripts, HEIF, image
embeddings/semantic search, cloud OCR, thumbnails, and any periodic background
OCR worker (the current design only OCRs on app resume, trading background
throughput for battery correctness). The `OcrDetector` seam is the future
extension point.