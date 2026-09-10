# VoraFind — Android MediaStore Discovery Scanner

Status: **Implemented (Prompt #4 baseline)**
Target: Android 7.0+ (`minSdk 24`), compile/target `SDK 36`
Owner: VoraFind engineering
Last updated: 2026-09-11
Depends on: `docs/android-indexing-architecture.md` (design), `docs/android-permission-layer.md` (permissions)

---

## 1. Purpose

This document describes the shipped Android **discovery scanner**: a small Kotlin
layer that enumerates MediaStore metadata for images, videos, and audio and streams
the results to Flutter in bounded, ACK-gated batches.

Discovery is **scanning only**. Nothing here persists, indexes, or searches. The
future Drift/SQLite index, search engine, and OCR live in Dart/app layers and are out
of this document's scope.

### Confirmed non-goals (Prompt #4 scope boundary)

The scanner deliberately does *not*:

- touch `MediaStore.Files` or any filesystem crawling;
- read or decode file bytes (no thumbnails, EXIF, perceptual hashing, OCR, hashing);
- scan documents (SAF grants remain the future mechanism);
- persist anything, run a database, or build a search index;
- schedule work (no WorkManager, foreground services, or notifications);
- trigger permission prompts; and
- run any network traffic.

---

## 2. Channel Contract

Channels are declared in `DiscoveryBridge.kt` (Kotlin) and mirrored by
`lib/core/platform/media_discovery.dart` + `media_discovery_models.dart` (Dart).
Wire contract version: `1`.

### MethodChannel `vorafind/indexing`

| Method | Arguments | Result |
| --- | --- | --- |
| `startDiscovery` | `categories: ["images"\|"videos"\|"audio"]` | `DiscoveryStartResult` (accepted, contractVersion, code?, categories[]) |
| `ackBatch` | `sequence: Int` | `bool` (acked / false for stale/unknown/duplicate) |
| `cancelDiscovery` | — | `bool` (true if a cancel was issued) |
| `getDiscoveryStatus` | — | `DiscoveryStatus` snapshot |

Errors: `invalidArguments`, `discoveryStartFailed` (method-channel level).
Refusals that are *normal outcomes* are returned as `accepted=false` with a code:
`busy`, `eventListenerNotAttached`, `invalidArguments`.

### EventChannel `vorafind/indexing/events`

All events are typed maps with a `type` discriminator; unknown types raise
`FormatException` in Dart (never silently dropped):

`discoveryStarted` (per category/volume), `discoveryBatch` (records, hasMore,
skippedCount, generationAfter), `discoveryProgress` (running totals, emitted after
each gated batch), `discoveryCompleted`, `discoveryCancelled`, `discoveryError`.

Sequence and ACK protocol:

- Every non-empty page is delivered as one `discoveryBatch` with a monotonically
  increasing `sequence`.
- A batch whose `hasMore == true` **gates the next page**: the scanner blocks until
  the Dart side calls `ackBatch(sequence)` (window = 1, no more than one outstanding
  batch). `recordsDiscovered`/`batchesSent`/progress events are only advanced *after*
  the gating batch is acked.
- A terminal batch (`hasMore == false`) requires no ACK — the session completes
  without waiting, so an un-acked final batch can never strand the scanner.
  Acking a terminal batch is a harmless no-op that still returns `true`.
- `ackBatch` returns `false` for unknown sequences, for a sequence that is no longer
  current, and for a duplicate ACK of a gating batch.

The Dart facade exposes `events()`; subscribe **before** `startDiscovery`, otherwise
the native side refuses with `eventListenerNotAttached`.

---

## 3. Access Integration (capability-aware scanning)

The scanner reuses the Prompt #3 permission layer (`MediaPermissionService`,
`ContentAccessBridge`) and never requests permissions itself.

At `startDiscovery`, each requested category is classified from
`MediaPermissionService.stateFor(category)`:

| Platform state | Category status (`accessScope`) |
| --- | --- |
| FULL_ACCESS | `started` (`full`) |
| PARTIAL_ACCESS | `started` (`partial`) — only the user-selected photos/media visible through MediaStore are scanned |
| NO_ACCESS / DENIED / PERMANENTLY_DENIED / NOT_REQUIRED | `unavailable` — category is skipped, never scanned, no error |

`documents` is always `unavailable` here (SAF-scoped, Prompt #5+). Flutter must call
`startDiscovery` only after prompting for permissions itself; the scanner never shows
dialogs. A category that reports `partial` is scanned exactly as MediaStore presents
it — unselected items are simply not visible to this app and are **not** treated as
deleted.

---

## 4. Collections and Volumes

### Collections (typed, never `MediaStore.Files`)

| Category | Collection |
| --- | --- |
| images | `MediaStore.Images.Media` |
| videos | `MediaStore.Video.Media` |
| audio | `MediaStore.Audio.Media` |

### Volumes

- API 29+: `MediaStore.getExternalVolumeNames(context)` sorted; one plan per volume.
- API < 29: a single nominal volume `"external_primary"` (no volume API exists).

### Selection

- API 29+: `IS_PENDING = 0`.
- API 30+: additionally `IS_TRASHED = 0`.
- API < 29: no implicit filter (columns do not exist).
- Keyset condition `_ID > ?` (see §6) is appended to every continuation query.

### Projections (explicit per category)

Common: `_ID`, `DISPLAY_NAME`, `MIME_TYPE`, `SIZE`, `DATE_ADDED`, `DATE_MODIFIED`,
`BUCKET_DISPLAY_NAME`, `DURATION`.

- images/videos additionally: `WIDTH`, `HEIGHT`;
- audio additionally: `TITLE`, `ARTIST`, `ALBUM`;
- API 29+: `RELATIVE_PATH`, `VOLUME_NAME`.

Rows are read with the nullable column adapter (`MediaStoreRow`);
provider/API-version column absence degrades to null — never a failure.

### Generation metadata (capture only — no delta scanning)

`MediaStore.getGeneration(context, uri)` is captured once per collection page and
carried as `generationAfter` on batches (API 30+, null below; on API 34+ the
native signature accepts the URI string). It is **metadata only**: this baseline
performs no generation-based or incremental re-scan.

---

## 5. Record Structure

`MediaDiscoveryRecord` (Kotlin) mirrors `MediaDiscoveryRecord.fromJson` (Dart). All
values are MediaStore metadata; never file bytes.

| Field | Notes |
| --- | --- |
| `category`, `volumeName` | Scan context |
| `mediaStoreId` | `_ID` within the volume's collection |
| `stableKey` | `"volumeName:mediaStoreId"` — primary identity (architecture §8.1) |
| `relinkSignature` | SHA-256 of `RELATIVE_PATH\|DISPLAY_NAME\|SIZE\|DATE_MODIFIED`; `null` when `RELATIVE_PATH` is unavailable (API < 29). Enables remapping after MediaStore rebuilds/renumbers `_ID`s. Metadata only. |
| `contentUri` | Canonical `content://…` (collection + `_ID`) — the future indexer's addressing anchor |
| `displayName`, `mimeType`, `sizeBytes`, `dateAdded`, `dateModified` | Standard columns |
| `relativePath`, `bucketDisplayName` | `null` on API < 29 for `relativePath` |
| `width`, `height` | images and videos |
| `durationMs` | videos and audio |
| `title`, `artist`, `album` | audio |
| `screenshotScore`, `isScreenshot` | Derived hint, **images only** (see §7) |

### Screenshot classification (architecture §17, non-authoritative)

Pure metadata scoring: strong 60 — path/bucket contains `screenshot`
(case-insensitive) or AOSP filename `Screenshot_yyyyMMdd-HHmmss(.ext)`; medium 35 —
OEM prefixes (`screenshot_`, `screenshot-`, `screencapture`, `skcapture`); low 10 —
plausible picture size (50 KB–25 MB) with `image/png|jpeg|webp`. Score capped at 100;
`isScreenshot = score >= 60`. This is a hint for ranking later, never a hard label.
No decoding, no OCR.

---

## 6. Batching, Pagination, and Resource Use

- **Keyset pagination:** `SELECT … WHERE _ID > :lastId ORDER BY _ID ASC`, one page at
  a time; never 50k-row payloads, never a full-library list in memory.
- **Batch size:** default 500 records; a page never exceeds it.
- **Exact `hasMore`:** the assembler reads at most `batchSize + 1` rows and reports a
  page as exhausted only after proving one more keyset query returns nothing.
- **Skipped rows:** a row that cannot be mapped (e.g. missing `_ID`) is skipped and
  counted (`skippedCount`), it never fails the page or the library.
- **Keyset advance on fully-skipped pages:** `QueryPage.lastBatchId` advances the
  cursor even when every row in a page failed mapping. A provider that returns rows
  with no identity *and* a `hasMore` page is treated as a scanner-level failure
  (`discoveryError`, code `scannerFailed`) rather than an infinite loop.
- **Cursors:** always closed (`use { … }`) on success, exception, or cancellation.
- **Cancellation:** checked per row and between pages; `cancelDiscovery()` is
  thread-safe, idempotent, safe in every lifecycle state, and unblocks a scanner
  currently waiting on an ACK. A cancelled session emits `discoveryCancelled`.

### Threading

All MediaStore/scan work runs on a single daemon thread (`vorafind-discovery`);
events are emitted only from that thread. There is no `WorkManager`, no foreground
service, and no uncontrolled pool.

---

## 7. Lifecycle & Progress

Scanner states (wire): `idle`, `running`, `completed`, `cancelled`, `failed`.

- One live session at a time; `startDiscovery` while running returns
  `accepted=false, code=busy`.
- Start requires an attached event listener (`eventListenerNotAttached` otherwise).
- Progress is real, not fabricated: `discoveryProgress` after each gated batch carries
  `recordsDiscovered`, `skippedRecords`, `batchesSent`, and `batchesRemaining`
  (0 or 1). There are no percentage estimates and no pre-count queries.
- Terminal events are exactly one of `discoveryCompleted` / `discoveryCancelled` /
  `discoveryError`, and the scanner never auto-resumes.

---

## 8. Failure Isolation & Logging

- Per-row mapping failures: skip + count.
- Per-collection/scanner failures (e.g. permission revoked mid-scan): terminate
  cleanly with `discoveryError { code: "scannerFailed", message }`, state = `failed`.
- Log lines are concise and never contain file contents; file paths are treated as
  privacy-sensitive.

---

## 9. Privacy

As mandated by AGENTS.md §8/§10 and the architecture §19: zero network, no backend,
no analytics of content, no file bytes crossing the channel, everything stays
on-device. No new permissions were added (reuses Prompt #3's five media permissions;
no `MANAGE_EXTERNAL_STORAGE`).

---

## 10. Tests

- **Kotlin (JVM):** `ScreenshotClassifierTest`, `RelinkSignatureTest`,
  `MediaRowMapperTest`, `QueryPageAssemblerTest`, `DiscoveryEngineTest` (engine ack
  protocol, cancellation in all states, capability-aware skipping, multi-volume
  ordering, failure isolation, terminal-batch completion).
- **Dart:** `media_discovery_models_test.dart` (every event/record decode + unknown
  type rejection), `media_discovery_facade_test.dart` (method channel invocation and
  arguments, error mapping, event-stream decode over a mocked EventChannel).

---

## 11. Deferred (documented, not implemented)

- Drift/SQLite persistence, FTS/search, OCR, PDF/document indexing, embeddings/AI,
  thumbnails, perceptual hashing, duplicate/face detection, waveform analysis.
- SCHEDULED/resumable/incremental scanning (generation deltas, `DeletedFiles`).
- SAF document-tree scanning and the Downloads folder.
- UI surfaces for discovery (progress screens) and permission flows.
- A dedicated Android instrumentation suite (device-dependent; JVM coverage is kept
  dependency-free by design).