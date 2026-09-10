# VoraFind — Android Content Discovery & Indexing Architecture

Status: **Partially implemented — the MediaStore discovery scanner baseline has
landed and matches this document's §6 (Kotlin owns MediaStore), §8.1 (stable
identity/re-link signature), §11 (bounded batched, ack-gated delivery), §13
(channel contract), and §17 (screenshot heuristic). The Drift/SQLite index, search,
OCR, and scheduled/resumable indexing remain unimplemented.**

> Concrete implementation details, the exact channel contract, projections,
> selection gating, and the record schema live in **`docs/android-discovery.md`**.

Target: Android 7.0+ (`minSdk 24`), compile/target `SDK 36`
Owner: VoraFind engineering
Last updated: 2026-09-11

---

## 1. Executive Summary

VoraFind's core promise is "Find anything you've saved on your phone." Before we can
search anything, we need a reliable, private, on-device content-discovery and indexing
pipeline. This document defines that pipeline's architecture for Android.

The recommended architecture is:

1. **Kotlin owns discovery.** A small native layer queries `MediaStore` (media files)
   and persists user-known document trees via the Storage Access Framework (SAF).
   It exposes content as a typed, streaming, event-based contract to Flutter. Kotlin
   never owns the database, the search index, or the app's business logic.
2. **Flutter owns persistence, orchestration, and search.** Flutter consumes discovery
   batches over a channel and writes them into the SQLite (Drift) index. The indexing
   state machine (start/pause/resume/cancel/idle/completed/failed) lives in Dart.
3. **Privacy-first by construction.** Only metadata is indexed in the MVP. No file
   bytes, no OCR text, no thumbnails, no location, no network. All data stays on device.
4. **No broad permission shortcut.** The MVP does **not** request
   `MANAGE_EXTERNAL_STORAGE`. Media is read through `READ_MEDIA_IMAGES/VIDEO/AUDIO`
   (with the Android 14+ partial-access fallback). Documents are read through
   user-chosen SAF folder grants. This is the Google-Play-safe path and the
   privacy-honest path.
5. **Resumable, cancellable, and failure-tolerant.** Indexing is batched, checkpointed
   after every batch, and designed as a pipeline where one corrupt or unsupported file
   never stops the whole run.

---

## 2. Android API Research (verified against Google's current documentation)

This section captures the concrete API facts the architecture relies on. Every claim
was checked against `developer.android.com` reference pages before being included.

| API | Method / Column | Notes |
| --- | --- | --- |
| API 1 | `MediaStore.Images`, `.Video`, `.Audio` collections | Legacy top-level media query entry points. |
| API 24 | — | Our `minSdk`. Pre-scoped-storage era. |
| API 25 | `IS_FAVORITE` | Favorite flag exists but writes are legacy; prefer `createFavoriteRequest` (API 30) later. |
| API 28 | `READ_EXTERNAL_STORAGE` | Full read of shared storage on ≤ API 28 (legacy storage model). |
| API 29 | `RELATIVE_PATH`, `VOLUME_NAME`, `IS_PENDING`, `INFERRED_DATE`, `MediaStore.getVersion()`, `MediaStore.Downloads` collection, `MediaStore.Files` scope change | Start of scoped storage. `DATA` column starts being redacted. `MediaStore.Images/Video/Audio.TRASHED` projectable. |
| API 30 | `GENERATION_ADDED`, `GENERATION_MODIFIED`, `MediaStore.getGeneration()`, `IS_TRASHED`, `IS_DOWNLOAD`, `DATE_EXPIRES`, `RESOLUTION`, `OWNER_PACKAGE_NAME`, `MediaStore.Downloads.setDownloadUri` | Generation-based change tracking becomes available — this is the anchor for incremental indexing. |
| API 33 | `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO` | Replacement for `READ_EXTERNAL_STORAGE` on Android 13+; granular media permissions. |
| API 34 | `READ_MEDIA_VISUAL_USER_SELECTED`, `QUERY_ARG_LATEST_SELECTION_ONLY` | Android 14 "Selected Photos Access". Partial grants exist; unselected items are invisible to the app. |
| API 35 | Partial-selection persistence | On Android 15+, user-selected media access persists across app restarts for apps targeting SDK 35 (previously session-scoped). Selection can be expanded incrementally. |
| API 36 | `MediaStore` user-grant API + locked-down version strings; background job/integrity semantics changed | Our `targetSdk`/`compileSdk`. Version strings are no longer globally comparable — never parse `getVersion()`. |
| API 37 | `MediaStore.DeletedFiles` / `MediaStore.queryDeletedFiles()` | A public API for enumerating recently deleted rows (recent api diff). Too new to be the primary mechanism, but usable as an accelerator with a rebuild-level fallback. |

Key conclusions from this table:

- **Incremental change tracking for media** is best served by `MediaStore.getGeneration()`
  (API 30+) combined with `GENERATION_ADDED`/`GENERATION_MODIFIED` columns. The
  generation counter is monotonically increasing and robust to clock changes and
  `setLastModified` calls — unlike `DATE_ADDED`/`DATE_MODIFIED`.
- **`getVersion()` must not be treated as a global monotonically-increasing number.**
  Use it only as an opaque signal that "the store changed shape; run a lightweight
  sweep." On API 36 the returned value is per-app and can go backwards.
- **Deletion detection cannot rely on a public API today.** With `minSdk 24` and a
  market that is mostly ≤ API 36, we must reconcile (diff our index IDs against the
  current query results) with the `DeletedFiles` table only used when available.

---

## 3. Supported Content Types (Capability Matrix)

The MVP indexes **metadata** for three broad categories. Anything not in a category
(filesystem trees, arbitrary binaries) is out of scope for the MVP unless the user
explicitly grants a SAF folder and even then only for recognized document types.

| Category | Android 13+ (`API 33+`) | Android 12− (`API 24–28`) | Discovery mechanism |
| --- | --- | --- | --- |
| Images (incl. screenshots) | `READ_MEDIA_IMAGES` (full) or `READ_MEDIA_VISUAL_USER_SELECTED` (partial) | `READ_EXTERNAL_STORAGE` | `MediaStore.Images` |
| Videos | `READ_MEDIA_VIDEO` (or partial) | `READ_EXTERNAL_STORAGE` | `MediaStore.Video` |
| Audio | `READ_MEDIA_AUDIO` (full only — no audio partial-access) | `READ_EXTERNAL_STORAGE` | `MediaStore.Audio` (+ tags healthy) |
| Documents/PDFs/text (user-chosen folders only) | SAF tree grant (`ACTION_OPEN_DOCUMENT_TREE`) or per-file `ACTION_OPEN_DOCUMENT` (multi-select) | SAF (identical) | SAF document tree/provider. **Not visible through MediaStore under scoped storage.** |
| Other binaries / system files | Not indexed (MVP). Requires all-files access, not in MVP. | `MediaStore.Files` (+ READ) | — |

Design consequence: on modern Android the "index everything" experience is bounded by
permission scope. Search quality for **media** is high. Search quality for **documents**
depends on whether the user granted a SAF folder. This is presented honestly in the UI
(see §4).

---

## 4. Permission Strategy

Goal: index as much shared content as the platform lawfully allows with the *narrowest*
permission set, respecting Android 14+ partial access and Google Play policy.

### 4.1 Default matrix

| Android version | Permissions requested | Scope achieved |
| --- | --- | --- |
| 13+ | `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO` | Full media library (broad grant). The OS may offer the Android 14+ *Selected Photos Access* picker; in that case `READ_MEDIA_VISUAL_USER_SELECTED` is auto-granted instead. |
| Android 14 (partial grant) | `READ_MEDIA_VISUAL_USER_SELECTED` (auto via system picker) | Indexes only the user-selected subset. UI shows "some items may be missing" banner. |
| ≤ Android 12 (`API 24–28`) | `READ_EXTERNAL_STORAGE` | Full shared storage read (legacy model), including all MediaStore.Files entries. |
| All versions | Media above | Plus SAF tree grant(s) chosen by the user for documents. |

### 4.2 Explicit non-decisions

- **No `MANAGE_EXTERNAL_STORAGE` in the MVP.** It is a restricted "All files access"
  permission. Google Play allows it for core-functional uses ("File managers",
  "On-device search", "Document management") but requires a permissions-declaration
  form and demotion/removal otherwise. It is aversive for privacy (a user would
  rightly distrust an app asking for total disk access), it breaks the Android
  permission model, and — decisively — the MVP can achieve its product promise without
  it: media is accessible via fine-grained permissions, documents via user-granted SAF
  trees. Revisit only as an explicit, separately-approved power-user extension, never
  as the default.
- **No `WRITE_EXTERNAL_STORAGE` / no write access at all.** VoraFind never writes to
  the user's shared storage in the MVP.
- **No `ACCESS_MEDIA_LOCATION`.** Reading GPS coordinates from photo EXIF is a separate
  runtime permission and a serious privacy concern. PRD mentions
  "metadata location where available and permitted" — that is explicitly deferred and
  gated behind its own confirmation before implementation.
- **No `Android Photo Picker` as an indexing mechanism.** The photo picker is a
  user-selection UI; it does not enumerate an indexable library. It is a future
  shortcut for "add specific photos", not a base for "search everything".

### 4.3 Google Play policy (must be handled before any store submission)

- Broad `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` access requires a **core-functionality
  declaration** on the Play Console (policy deadline long passed; this affects all
  "standard" photo/video apps). VoraFind's core = on-device search over the user's
  media library. This is materially the same category as gallery/file-management apps.
  We must file the declaration and be able to justify it.
- Support for **partial access** (letting users select photos) is the policy-preferred
  path Google is steering apps toward. VoraFind must *honor* partial access (index
  what is granted, never pretend deletion, show a status banner).
- `READ_MEDIA_AUDIO` is a separate "sensitive" permission but does not have the photo
  policy's special declaration; still treat it as core-only.

---

## 5. Storage & Scoped-Storage Strategy

- **minSdk 24 / target 36** — scoped storage is mandatory on API 29+ (we target 36).
  On API 29–28 the legacy full-shared-storage read model applies and
  `MediaStore.Files` exposes everything, including non-media files.
- **Volumes.** Enumerate with `MediaStore.getExternalVolumeNames()` +
  `MediaStore.getRecentExternalVolumeNames()` (API 29+). Query each collection
  per-volume. State machine keys on `(volume-name, media-type)`.
- **Removable storage (SD cards).** Under scoped storage, third-party apps get *media*
  coverage on removable volumes via MediaStore; arbitrary document trees require a SAF
  grant scoped to the removable device. `RELATIVE_PATH` includes the volume-relative
  path; never build absolute paths as identity.
- **App-private storage is never indexed.** `getExternalFilesDir`, `getCacheDir`, and
  other app-protected areas are outside the product's promise and a privacy hazard.
  Excluding them is a hard rule.
- **`MediaStore.Downloads` is only app-owned.** Other apps' downloads are invisible
  under scoped storage. This is why documents use SAF (§7).

---

## 6. MediaStore Strategy

### 6.1 Primary entry points

| Need | Entry point |
| --- | --- |
| Full incremental scan | `Images`, `Video`, `Audio` collections per volume, with `GENERATION_*` predicates (API 30+) |
| Change counter | `MediaStore.getGeneration(uri)` (API 30+) |
| Shape-change signal | `MediaStore.getVersion(uri)` — opaque; triggers a lightweight sweep, never a permanent reliance |
| Store reset / external changes | Version-change → full resync guaranteed-correct path |
| Pending/trashed | `IS_PENDING = 0`, `IS_TRASHED = 0` in all queries (API 29+) |
| Reconciliation | Re-query IDs and diff against index (see §9) |

### 6.2 Projection policy

Fetch exactly the metadata we persist. In order of preference (never request `DATA`
on API 29+; it is redacted and unstable):

```
_ID, DISPLAY_NAME, MIME_TYPE, SIZE, DATE_ADDED, DATE_MODIFIED,
DATE_TAKEN (images/video; fall back to INFERRED_DATE),
RELATIVE_PATH (API 29+), VOLUME_NAME,
WIDTH, HEIGHT (MediaColumns API 29+; media-specific columns on lower APIs),
DURATION (MediaColumns API 29+; audio AudioColumns legacy),
BUCKET_DISPLAY_NAME, IS_FAVORITE,
GENERATION_ADDED, GENERATION_MODIFIED (API 30+ projection when present)
```

No `DATA`, no `_data` reads. No thumbnail columns. No EXIF in discovery.

### 6.3 Query discipline

- Order by `_ID` and use **keyset pagination** (`WHERE _ID > ?cursor ORDER BY _ID`),
  not `OFFSET`. Keyset pagination stays stable as the table mutates mid-scan.
- Pass a `CancellationSignal` to every query; check it per row so cancel is ~instant.
- Coalesce small column reads; avoid per-row binder round-trips.
- All projections/column existence checked via `Build.VERSION` gates (see §21 matrix).

---

## 7. Documents / Downloads Strategy (SAF)

Problem: under scoped storage, documents (PDF, DOCX, TXT, APK, ZIP, …) from other
apps are **not** enumerable through MediaStore at all.

Solution — Storage Access Framework with **user-chosen folder grants**:

- **`ACTION_OPEN_DOCUMENT_TREE`** (API 21+): ask the user to pick a folder, e.g.
  "Documents", "OneDrive/…", "Downloads/…" subfolder. Retrieve a
  `content://…/tree/…` URI, persist it with `takePersistableUriPermission`
  (granting `FLAG_GRANT_READ`), and enumerate with
  `DocumentsContract.buildChildDocumentsUriUsingTree`.
- **Per-file fallback `ACTION_OPEN_DOCUMENT`** (API 19+, multi-select): for users who
  won't grant a whole tree (or for ad-hoc grabs). Each file gets a persisted read grant.
- **SQLite roots are grayed out** on Android 11+ in the tree picker (`Storage Volume`,
  SD-card root, and the `Download/` root). Subdirectories of `Download/` are
  selectable. This is a platform rule; the UI must steer users to pick a folder *under*
  Downloads when they intend to index downloads.
- **Enumeration limits:** SAF child-listing is per-directory and notoriously thinner than
  MediaStore's bulk cursor. For MVP we walk the granted tree recursively but with a
  depth cap (e.g., 8) and a total cap reported in the UI (configurable constant).
- **Identity for SAF documents** is the canonical tree-relative document path plus the
  tree URI authority (see §8).

UX contract (stated honestly):
> "Indexed documents: only the folders you choose. Tap to add a folder."

---

## 8. Stable Identity Strategy

Identity is the spine of incremental indexing and deletion detection. Mistake here
costs correctness, so the rules are explicit.

### 8.1 MediaStore items

- **Primary key:** `volumeName` + `_ID`. Example: `"external_primary:12345"`.
  `_ID` is stable for the life of a MediaStore row and survives path changes —
  unlike `RELATIVE_PATH`/`DATA`.
- **Re-link signature (secondary):** MediaStore can rebuild (factory reset of the
  MediaStore cache, external storage events), renumbering `_ID`s. A secondary
  signature — SHA-256 of `(RELATIVE_PATH | DISPLAY_NAME | SIZE | DATE_MODIFIED)` —
  lets us remap an old stable key to a new `_ID` once, then continue on the new key.
- **Never** derive identity from absolute path strings (`/storage/emulated/0/…`).
  Absolute paths rotate; `DATA` is redacted on 29+.

### 8.2 SAF documents

- **Primary key:** canonical `treeUri` authority + tree-relative path
  (`DocumentsContract.getDocumentId` → decode & join the path segments).
- **Content URI derivation:** stored identity must be reconstructible without
  re-querying, because re-querying may fail if the tree was unselected later. We keep
  the full tree URI in the volumes table and only rebuild the document URI on demand.

### 8.3 Stability rules enforced during indexing

1. Insert is an **upsert on stable key** (idempotent).
2. A row whose signature changes *and whose generation is newer* is an **update**,
   not delete+insert.
3. A row that disappears from MediaStore while we hold full-scope is a **deletion**;
   a row that disappears while scope is partial is **unresolved** (§9.3).

---

## 9. Incremental Indexing Strategy

### 9.1 The primary path — generations (API 30+)

For each `(volume, collection)`:

1. Read `getGeneration(collectionUri)`. If unchanged since our checkpoint, nothing to do.
2. Emit rows where `GENERATION_MODIFIED >= lastScannedGeneration` **or**
   `GENERATION_ADDED >= lastScannedGeneration`, ordered by `_ID` (keyset).
3. Update checkpoint to the last seen generation at batch boundaries (never mid-batch).

Generation is robust against wall-clock tampering (unlike `DATE_MODIFIED`).

### 9.2 The fallback path — version sweep

`getVersion()` describes table shape, not chronology. On a version change we run a
**lightweight sweep**: keyset-scan IDs only (cheap projection), diff against the index,
and mark deletes/updates. This is bounded and cheap because we never re-extract content.

### 9.3 Deletion detection (with access-scope guard)

The dangerous case: Android 14+ partial access makes unselected items **vanish from
our queries**. A naive "not in result = deleted" pass would wipe the index.

- **Guard:** deletion reconciliation runs only when the access scope at sync time
  equals the scope now (both full, or both partial with the same selected-set
  generation). Partial scope → we suspend deletion-logic for media and only add/update.
- **Mechanism (all API levels):** keyset diff of indexed IDs vs current IDs, chunked.
  Only entries absent for a minimum of N consecutive passes are hard-deleted, so a
  transient storage event never destroys the index.
- **Accelerator (API 37+, opportunistic):** if `MediaStore.queryDeletedFiles()` is
  available, consult it first to catch deletes cheaply. Never make it the only path.

### 9.4 What "incremental" covers at MVP

Photos/videos/audio added or (re)modified since last sync; screenshots arriving;
documents appearing in granted SAF trees. Content extraction (OCR) is decoupled
(§16) — a new photo gets *indexed* (metadata) immediately and *extracted* (OCR) later.

---

## 10. Initial Scan Strategy

1. **Trigger:** first launch after permissions granted (media) and/or first SAF tree
   grant (documents).
2. **Ordering:** (a) capture capabilities; (b) prompt permissions; (c) optional SAF
   folder onboarding; (d) start scan; (e) stream batches; (f) persist checkpoints.
3. **Foreground UX (in-app):** run the scan in-process on a background thread
   (`Dispatchers.IO`), streaming batches to Flutter; show progress, pause, resume,
   cancel controls. No artificial delay; the first few hundred rows should land in
   under a second.
4. **Background continuation:** if the user backgrounds the app mid-scan, the current
   batch completes, the checkpoint is persisted, and the remainder is handed to the
   background worker (§14). The scan is always resumable from the last committed batch.
5. **Cold-start guarantee:** media indexing must feel "searchable" within seconds of
   launch — even while a long tail of OCR work is still pending.

---

## 11. Batch Strategy

- **Batch shape (discovery):** a `DiscoveryBatch` event carries ~`BATCH_SIZE`
  metadata rows (default **500**, calibrated by measurement) plus `volume`,
  `collection`, `accessScope`, `generationAfter`, `checkpoint`, `hasMore`,
  `sequence`.
- **Batch content policy:** metadata only. No bytes, no thumbnails, no OCR, no EXIF
  blob. One batch must fit comfortably in memory (< a few MB).
- **Backpressure:** Flutter acks each batch (`ack(sequence)`); Kotlin stalls the
  cursor until the ack arrives. This bounds memory on both sides and makes the pipeline
  resumable at batch granularity.
- **Persistence cadence:** the DB transaction for a batch commits before the next batch
  is requested. A crash = at most one lost batch, re-fetched by re-running from the
  last committed checkpoint.
- **Failure isolation:** per-item try/catch inside Kotlin; a corrupt/missing row is
  skipped and recorded in the native error feed, never propagated to Flutter as a
  fatal.
- **Cancellation:** checked between every keyed page and every row; a cancelled run
  writes the checkpoint reached so far.

---

## 12. Flutter ↔ Kotlin Boundary

### 12.1 Decision

**Kotlin owns capability/permission queries, MediaStore+SAF enumeration, stable-key
derivation, content-URI resolution, and thumbnail access. Flutter owns orchestration,
persistence (Drift), the index, search, and UI. Kotlin is a resumable, stateful scan
*engine* — but it is stateless regarding app logic: it never opens the DB and never
decides what to keep.**

Why this hybrid (vs. all-Kotlin):
- AGENTS.md demands we not move business logic to Kotlin without reason. Search,
  ranking, and app state have no platform dependency — they belong in Dart.
- MediaStore/SAF/permissions content access *is* platform work — it belongs in Kotlin.
- The bridge stays small, typed, and documented.

### 12.2 Channel technology

Use **`MethodChannel` for commands** and an **`EventChannel` for the batch/status
stream**, both wrapped in a single hand-written, strongly-typed Dart facade
(`IndexingBridge`) and a matching Kotlin `DiscoveryService` that drives the native
scanner.

- Justification: two request/response commands and one event stream are the entire
  surface; `MethodChannel`+`EventChannel` have negligible overhead and zero codegen.
- `Pigeon` (typed codegen) would be the upgrade path if the API grows; it is **not**
  added now (no dependency for architectural fashion, per AGENTS.md dependency rules).
- Every message payload is versioned (`contractVersion`) so Kotlin and Dart can detect
  a drift at startup instead of failing mid-scan.
- Runtime permission requests and the SAF picker use the platform
  **Activity Result API** (`ActivityResultContracts`) behind the facade, so
  `MainActivity` must extend `FlutterFragmentActivity` (which provides
  `registerForActivityResult`) rather than plain `FlutterActivity`. See
  `docs/android-permission-layer.md`.

---

## 13. Communication Contract

### 13.1 Surface

Commands (Dart → Kotlin, `MethodChannel "vorafind/indexing"`):

| Method | Args | Returns |
| --- | --- | --- |
| `getCapabilities` | — | `{platformVersion, apiLevel, permissionState, partialAccess, safCapable, mediaStoreGenerationSupport}` |
| `checkPermissions` | — | structured permission state per collection |
| `openPermissionScreen` | collection | success flag |
| `startDiscovery` | `{volumes?, collections?}` | `{accepted, contractVersion}` |
| `pauseDiscovery` | — | checkpoint flushed? |
| `resumeDiscovery` | — | success flag |
| `cancelDiscovery` | — | success flag |
| `getDiscoveryStatus` | — | `{state, completedBatches, totalItems, lastCheckpoint}` |
| `grantDocumentTree` | — | yields URI (invokes SAF picker inside native, returns tree identity) |
| `resolveContentUri` | stableKey | content URI or error (used by later content phases) |

Events (Kotlin → Dart, `EventChannel "vorafind/indexing/events"`):

| Event | Payload |
| --- | --- |
| `discoveryStarted` | `{volume, collection, accessScope}` |
| `discoveryBatch` | `DiscoveryBatch` (§11) |
| `discoveryProgress` | `{completedItems, percent, phase}` |
| `discoveryCheckpoint` | `{volume, generation, itemCount, atRow}` |
| `discoveryCompleted` | `{summary}` |
| `discoveryPaused` / `discoveryResumed` | — |
| `discoveryCancelled` | — |
| `discoveryError` | `{code, message, recovered}` |
| `skippedItem` | `{stableKey, reason}` (failure isolation) |
| `permissionChanged` | new permission state |

### 13.2 Flow-control rules

- Kotlin emits a batch only after the previous one was acked (window = 1 in MVP;
  a small window ≤ 3 can be measured later).
- If the channel dies mid-stream (app background/system pressure), checkpoints already
  persisted win; on reconnect, Kotlin resumes from the last acked batch.
- All timestamps and sizes are UTF-8/JSON-clean; no platform types (no `ByteBuffer`,
  no custom Parcelables) leak across the channel.

---

## 14. Background Execution Strategy

Constraint (Android 16, respected across versions): background jobs that run from a
foreground service must obey running-time quotas (per standby bucket); user-initiated
*data-transfer* jobs are exempt from ordinary quotas but are sized/estimated workloads
by design, and `mediaProcessing` (API 35+) has its own 6-hour budget. We must not aim
for a permanent service.

Design:

1. **In-process when visible.** All indexing that happens while the app is in
   foreground runs in the app process on a background thread. No service needed.
2. **Chunked maintenance workers (the norm).** `WorkManager` runs incremental scans as
   short (`≤ 10 min`) resumable workers (`AudioTrack`-style chained workers updating
   checkpoints). Each worker is idempotent and self-terminating. No continuous service.
3. **Long-running initial pass (the exception).** The *user-triggered* first full index
   may outlive a single worker. It promotes to a `foregroundServiceType`-declared
   service only while actively scanning, and is cancellable from the ongoing
   notification:
   - API ≥ 35: `mediaProcessing` FGS has a 6-hour budget — fits the initial scan; if
     the type proves rejected for OCR-labeled work, fall back to a `dataSync`-type FGS
     (API 29+) or keep chunked WorkManager workers.
   - API 29–34: `dataSync` FGS type with notification.
   - API < 29: plain foreground service with notification.
4. **No periodic battery-drain.** Incremental checks are coalesced, skip when
   `ACTION_POWER_CONNECTED`/battery-saver active, and respect Doze.
5. **Resumability requirement** is designed in from batch 0; the worker may be killed
   at any checkpoint boundary with zero rework.

All background work goes through a single `IndexingCoordinator` in Dart that owns the
state machine: `idle | running | paused | completed | failed`.

---

## 15. Database Boundary

Flutter owns persistence via Drift/SQLite. The schema boundary is defined here to keep
discovery and future search cleanly separated.

### 15.1 Tables (MVP)

- **`volumes`** — one row per discoverable root:
  `id`, `type (mediastore|saf)`, `name`, `uri`, `generation`, `scopedGeneration`,
  `version`, `accessScope (full|partial|null)`, `lastSyncAt`, `state`.
- **`indexed_items`** — the metadata index (single source of truth for *what we
  know*):
  `stableKey (PK)`, `volumeId (FK)`, `mediaType`, `mimeType`, `displayName`,
  `relativePath`, `parentFolder`, `sizeBytes`, `dateAdded`, `dateModified`,
  `dateTaken`, `width`, `height`, `durationMs`, `isFavorite`, `isScreenshot`,
  `origin`, `accessScopeAtInsert`, `generationModified`, `extractionState`,
  `lastSeenAt`.
- **`index_state`** — checkpoints: `volumeId`, `collection`, `lastRowCursor`,
  `lastGeneration`, `lastVersion`, `fullReconcileRequested`, `lastReconcileAt`.
- **`index_errors`** — failure isolation records: `stableKey`, `volumeId`, `code`,
  `message`, `retries`, `lastAttemptAt`, `resolved`.
- **`saf_grants`** — persisted tree URIs + grant flags + user label (documents).

(OCR-final text lands later in `extracted_text`; FTS tables land with search — **not**
in this phase, per scope control.)

### 15.2 Indexing rules

- `stableKey` is a declared `PRIMARY KEY`; `(volumeId, relativePath)`,
  `(mediaType, dateModified)`, `(isScreenshot, mediaType)`, `(generationModified)`,
  and `(lastSeenAt)` are indexed for incremental sweeps and future query plans.
- Writes are batched in the same transaction as the batch that produced them
  (no torn state visible to search).
- **Never store derived data without an invalidation path** (AGENTS.md §20): the only
  derived flags in MVP are `isScreenshot` (from the §17 heuristic, recomputable) and
  `extractionState` (a tristate that can be reset).
- No file bytes are ever written by the database layer.

---

## 16. OCR / Content-Extraction Boundary

Extraction is **out of scope for launch**, but the boundary is defined now so
discovery does not need to be re-architected later.

- Discovery (this doc) ends at **metadata in `indexed_items`**.
- Extraction is a **separate queue** keyed by `stableKey` (`extractionState`), driven
  by its own provider class that will read content via `resolveContentUri`.
- Extraction never blocks discovery; discovery never waits on extraction.
- OCR text, when implemented, is on-device only (ML Kit on-device or similar), stored
  in its own table, and searchable only after explicit opt-in where warranted.
- The screenshot utility of VoraFind is served immediately by filenames + folder +
  dates; OCR only *augments* it later.

---

## 17. Screenshot Detection

Requirement (PRD emphasis): screenshots are a first-class "I know I saved it"
artifact. Detection is a **heuristic with scoring**, never an absolute claim.

### 17.1 Signals

| Signal | Weight | Notes |
| --- | --- | --- |
| `RELATIVE_PATH`/`BUCKET_DISPLAY_NAME` contains `Screenshot` | strong | Stock AOSP writes `Pictures/Screenshots`; Samsung `DCIM/Screenshots`; Xiaomi gallery variants |
| Filename matches `Screenshot_yyyyMMdd-HHmmss(.ext)` via `ImageExporter` pattern | strong | AOSP `ImageExporter.java` pattern: `Screenshot_%1$tY%<tm%<td-%<tH%<tM%<tS`, on `Pictures/Screenshots`, written with `IS_PENDING=1` + 24 h `DATE_EXPIRES` |
| OEM-recognized prefix set: `Screenshot_`, `Screenshot-`, `ScreenCapture`, `screenshot_…`, `SKCapture`, `IMG_…Screenshot` | medium | Curated, versioned table of OEM patterns (Samsung, Xiaomi, OPPO, OnePlus, Pixel, OneUI) |
| Media type ∈ {png, jpeg, webp}; full-bleed colors + plausible size for a snapshot | low | Cheap weight, no histogram deep-dive at MVP |
| `IS_PENDING` + later content check | weak | `IS_PENDING` is gone by the time we index post-quota; heuristics dominate |

### 17.2 Scoring rule

`score = weighted sum ≥ threshold ⇒ isScreenshot = true` (score stored as a
probability bucket in MVP, exact floats deferred). The rule table is data-driven and
unit-tested (§23 in this doc’s test plan — actually: tested under 53970 test matrix
in `test/`).

### 17.3 Known misses (honest limitations)

Samsung Secure Folder and other per-app vaults are invisible under scoped storage;
screen-recordings misnamed as screenshots; OEM apps writing to uncommon buckets.
Those items simply won't be flagged — the metadata index still has them.

---

## 18. Failure Handling

Hierarchy of guarantees:

1. **Item level:** an unparseable or phantom MediaStore row is skipped, recorded in
   `skippedItem`/`index_errors`, and never aborts the run.
2. **Batch level:** one failed batch (binder error, cursor invalidated) → re-query from
   the last checkpoint with a smaller batch size; after N retries, the batch is
   recorded and the *next* keyed-page is attempted. "One bad batch never ends the run."
3. **Run level:** fatal errors (permission revoked, volume unmounted, channel broken)
   transition the state machine to `failed` with a structured `discoveryError`, a
   persisted checkpoint, and a retry affordance in the UI.
4. **Recovery:** every transition is idempotent; re-running from any checkpoint is safe.
5. **Logging:** dev-only, no user content in log lines (filenames/paths may appear but
   not file contents; paths are scrubbed where privacy-sensitive).

---

## 19. Privacy & Security Model

- **Data-at-rest:** everything lives in app-private SQLite; indexed media metadata
  does not include bytes, embedded EXIF, GPS, or OCR text at MVP.
- **Data-in-motion:** zero network. No backend, no analytics of content.
- **Derived-data distinction:** `indexed_items` (derived metadata) vs. original files
  (untouched). Thumbnails/extracted text (future) live under app-private storage,
  clearly separate and re-derivable.
- **Platform:** no `ACCESS_MEDIA_LOCATION`, no all-files access, no microphone/SMS/
  contacts/location permissions; minimal manifest permissions only.
- **Channel security:** native→Dart events never carry file bytes; only stable keys.
- **Transparency:** consent single-purpose permission prompts ("Allow VoraFind to
  search your photos?"), SAF folder picker explaining exactly what gets indexed, and a
  Settings screen exposing per-volume scope.

---

## 20. Performance Strategy

Guiding principle (AGENTS.md §31): the app stays responsive during indexing; measure,
don't speculate.

1. **Threading:** all MediaStore/SAF work on `Dispatchers.IO` with `CancellationSignal`;
   DB writes in a transaction per batch; per-batch page len ≤ 500.
2. **Memory:** batch arrays capped; not entire library in RAM; keyset cursor, not
   offset list.
3. **Channel:** event window ≤ 3, ack-based; JSON sizes bounded (~≤1 MB per batch).
4. **Startup:** cold app never blocks on indexing; DB opened lazily; the first frame
   shows immediately and the scan reports progress as it goes.
5. **Metrics to calibrate before tuning any magic numbers:** batch build time,
   batch transfer time, per-batch DB commit time, cursor page time, memory delta per
   batch, and peak RSS during full scan on a 10k-image library. All `BATCH_SIZE`
   (default 500), page size, and channel-window constants are named constants,
   measured, and only tuned with data.
6. **No thumbnail generation in discovery.** (Later phases generate/clear thumbnails
   in a coalesced background queue.)

---

## 21. Android-Version Compatibility Matrix

| Concern | API 24–28 | API 29–32 | API 33 | API 34 (partial) | API 35+ |
| --- | --- | --- | --- | --- | --- |
| Storage model | Legacy (full via `READ_EXTERNAL_STORAGE`) | Scoped (media via MediaStore; SAF for docs) | same | same | same |
| Media permission | `READ_EXTERNAL_STORAGE` | `READ_EXTERNAL_STORAGE` | `READ_MEDIA_IMAGES/VIDEO/AUDIO` | + `READ_MEDIA_VISUAL_USER_SELECTED` possible | same |
| Partial access persistence | n/a | n/a | n/a | session-scoped | **persists across restarts** |
| Generation columns | n/a | n/a (gem on 30+) | yes (30+) | yes | yes |
| `getVersion` | n/a | 29+ | yes | yes | yes (36: per-app opaque strings) |
| Delete accelerators | reconcile only | reconcile | reconcile | reconcile (scope-guarded) | reconcile + `DeletedFiles` (API 37) |
| FGS types | plain FGS | `dataSync` | `dataSync` | `dataSync` | `dataSync` / `mediaProcessing` (35+) |
| `MediaStore.Files` (whole FS) | yes (legacy) | media only | media only | media only | media only |

**Code rule:** every column/method ≤ API 29 is queried only when `Build.VERSION.SDK_INT`
passes that gate, using a static capability table (computed once) rather than repeated
checks in hot paths.

---

## 22. Open Risks

| # | Risk | Mitigation / Plan |
| --- | --- | --- |
| R1 | **Play Store rejects broad photo/video access.** Core-functionality declaration is mandatory; content is a gallery/search app | File the declaration with a persuasive core-functionality write-up at store submission; keep partial-access support; do not ship all-files access. |
| R2 | **Partial access undermines completeness** (unselected items invisible) | Be explicit in UI; banner "some items may be missing — grant full access to search everything"; scope-guard deletion reconciliation (never wipe on partial). |
| R3 | **Documents only addressable via user grants; `Download/` root not tree-selectable (API 11+)** | SAF subtree under `Download/`; per-file fallback; folder onboarding in first-run. |
| R4 | **Deletion detection lacks a universal cheap public API** (DeletedFiles is API 37+) | Chunked ID-diff reconciliation with multi-pass grace; accelerator when present. |
| R5 | **OEM screenshot path divergence + Secure Folder invisibility** | Data-driven heuristic rule table (§17), versioned, testable; honest misses. |
| R6 | **Opaque/per-app `getVersion()` (API 36) breaks monotonic assumptions** | Use version only as "do a sweep" signal; generation numbers for chronology. |
| R7 | **Background execution quotas (Android 16) and FGS-type validation** | No permanent service; chunked workers; FGS only during user-triggered initial pass; verify FGS type acceptance during implementation. |
| R8 | **Channel/process death mid-scan** | Arbiter: all progress commits at batch boundaries; resume from last acked checkpoint. |
| R9 | **MediaStore rebuild renumbers `_ID`s** | Re-link signature (§8.1) remaps old keys. |
| R10 | **Volume unmount / SD-card removal during scan** | Per-volume state isolation; volume events mark `failed` for that store only; scan continues elsewhere. |
| R11 | **Battery impact of background refreshes** | Coalesced, quota-aware, `WorkManager`-backed, no periodic drain; respect Doze/battery-saver. |

---

## 23. Recommended Implementation Order

Ordered so each step produces a testable, shippable slice:

| Step | Deliverable | Exit criterion |
| --- | --- | --- |
| A | Native capability/permission layer | `getCapabilities`/`checkPermissions` correct per API level; unit-verified matrix |
| B | Typed bridge (Method/Event channels, JSON contract, versioning) | E2E echo test Dar→Kotlin→Dart |
| C | Single-collection MediaStore scanner with keyset paging + cancellation | 500-item synthetic media library scans & checkpoints correctly |
| D | Drift schema (volumes/indexed_items/index_state/index_errors) | Upserts idempotent; batching Tx commit per page |
| E | Initial full scan orchestration (state machine + progress UI) | Scan → done; pause/resume/cancel tested |
| F | Incremental & reconciliation (generation + version sweep + scope guard) | Add/update/delete detection tests pass, partial-scope non-destructive |
| G | SAF tree grant + document enumeration | Folder grant → OK; `Download/` root blocked UX handled |
| H | Screenshot heuristic engine (data-driven rule table) | Unit tests across AOSP + OEM patterns |
| I | Background coordination (`WorkManager` chunked + FGS-on-demand) | Worker resumability & quota behavior validated |
| J | Content access (resolve URI, open controller, thumbnails) | Item tap opens correct content / thumbnail renders |

Steps A–H are the "indexing pipeline" milestone (each independently releasable).
Search, ranking, OCR queue, and FTS are **later milestones** and must not be built
in this phase (AGENTS.md §27).

---

## 24. Explicit Decisions & Rejected Alternatives

| Decision | Chosen | Rejected | Why |
| --- | --- | --- | --- |
| Native volume | Kotlin for discovery/content; Flutter for state/db/search | All-Kotlin pipeline | AGENTS.md §7: keep bridge small; business logic stays in Dart. |
| Channel | `MethodChannel` + `EventChannel` (typed Dart facade) | Pigeon now | 3-method surface; no codegen dependency; Pigeon = later upgrade. |
| Permissions, media | `READ_MEDIA_IMAGES/VIDEO/AUDIO` (+ partial fallback) | `MANAGE_EXTERNAL_STORAGE`; photo picker as base | Play policy, privacy trust, app-visible store model; picker ≠ library enumeration. |
| Documents | SAF tree/per-file grants | `MANAGE_EXTERNAL_STORAGE`; guessing paths | Scoped storage hides non-media files; only SAF reaches them lawfully. |
| Identity | volume+`_ID` + re-link signature (media); tree-relative path (SAF) | Absolute path `DATA` | Paths rotate & redact; `_ID` stable; re-link survives MediaStore rebuilds. |
| Incremental | generation-first (`GENERATION_*`, API 30+), version sweep fallback | timestamp-only | Generation robust to clock drift; version is shape-only. |
| Deletions | chunked ID-diff reconciliation + scope guard; DeletedFiles accelerator | Trust `DATE_MODIFIED` alone; trust DeletedFiles as sole source | DeletedFiles public only on API 37; partial scope corrupts naive diffs. |
| Batching | keyset pages of ≤500 rows, ack-window ≤3, Tx-per-batch | Big single reads / whole-library cursors | Memory + resumability + channel bounded. |
| Background | chunked `WorkManager` workers; FGS only for user-triggered initial pass | Permanent FGS / do-it-all service | Android 16 quotas; battery policy; resumable design. |
| Screenshots | scored heuristic rule table | binary path check; ML later | OEM divergence; rule table is testable and honest. |
| Scope guard | suspend delete-reconcile under partial access | — | Correctness must not be sacrificed for speed on A14+. |

---

## 25. Recommended Architecture (Single Summary)

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Flutter (UI + Application)                                                  │
│  HomeScreen, IndexingSheet, Search sheet (future)                           │
│           │  IndexingCoordinator (state machine:                            │
│           │    idle|running|paused|completed|failed)                        │
│           │  IndexingBridge (typed facade over channels)                    │
├────────────────────────────────────────────────────────────────────────────┤
│ Data / Persistence (Flutter, Drift/SQLite)                                  │
│  volumes │ indexed_items │ index_state │ index_errors │ saf_grants          │
│  batch-aware transactions, stableKey PK, indexed columns                    │
├────────────────────────────────────────────────────────────────────────────┤
│ Kotlin — small native bridge                                                │
│  Discovery: MediaStore (keyset paging, generation, scoped read) + SAF        │
│  Checks: capabilities, permissions, partial-access, volume set               │
│  Content: resolveContentUri / later thumbnails                              │
│  Emits: DiscoveryBatch events (metadata only, ack-flow-controlled)          │
├────────────────────────────────────────────────────────────────────────────┤
│ Android platform                                                             │
│  MediaStore │ Storage Access Framework │ WorkManager / FGS(on-demand)        │
│  Permissions: READ_MEDIA_* (+ partial), SAF grants                           │
└────────────────────────────────────────────────────────────────────────────┘
```

Guarantees this architecture gives us:

- **Correct** — deletion/reconciliation, scope guards, version/generation separation.
- **Private** — no content bytes, no network, no all-files access, GPS deferred.
- **Fast** — keyset paging, batch streaming, in-app foreground scanning.
- **Resilient** — per-item/batch/run failure isolation, checkpoint resume.
- **Play-safe** — declared core functionality, partial-access honored, SAF for files.

---

## 26. Implementation Roadmap (Phases)

- **Phase 0 (foundation)** — repository, theme, Riverpod, analyzer/test wiring. *(done)*
- **Phase 1 (indexing pipeline)** — Steps A–J above; delivers metadata index for all
  media + user-chosen documents, incremental sync, screenshots hints, resumable
  background.
- **Phase 2 (search)** — deterministic search over the index (exact/keyword/fuzzy),
  ranking rationale, "matched in …" explanation strings.
- **Phase 3 (content UX)** — opening files, thumbnails, filter/collection views.
- **Phase 4 (extraction)** — on-device OCR / text extraction queue layered over
  discovery, never blocking it.
- **Phase 5 (optional extensions, each pre-approved)** — semantic search embeddings,
  duplicate detection, cross-device (stays local-first), power-user all-files mode.

Nothing in Phases 2–5 is implemented by the change that produces this document.

---

## References

- Android developer docs — `MediaStore`, `MediaStore.getGeneration`/`getVersion`,
  `GENERATION_ADDED`/`GENERATION_MODIFIED`, `RELATIVE_PATH`, `IS_PENDING`,
  `IS_TRASHED`, `ReadMediaVisualUserSelected`, `QUERY_ARG_LATEST_SELECTION_ONLY`,
  scoped storage (`data-storage/shared/media`), Storage Access Framework
  (`ACTION_OPEN_DOCUMENT_TREE`), `AndroidManifest` permissions reference,
  Android 13/14/15/16 behavior changes, `mediaProcessing`/foreground-service types,
  `UserInitiatedDataTransferJob`.
- AOSP `ImageExporter.java` (screenshot filename/path pattern).
- Google Play Console policies: photos/videos access, All files access
  (`MANAGE_EXTERNAL_STORAGE`).
- VoraFind `PRD.md`, `AGENTS.md`.