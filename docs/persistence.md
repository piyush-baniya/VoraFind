# VoraFind — Local Persistence & Index Storage

Status: **Implemented (Prompt #6) — Drift/SQLite `media_items` index,
transactional batch upserts, persist-then-ACK orchestration, `index_state`
checkpoints (schema v2), and a `SynchronizationCoordinator` that performs
generation fast-checks and bounded deletion reconciliation. Schema v3 (Prompt
#7) adds the normalized `searchable_text` retrieval projection with a paged
one-time backfill for pre-v3 rows.**

Last updated: 2026-09-11

---

## 1. Purpose

The discovery scanner (Kotlin, `docs/android-discovery.md`) streams bounded record
batches into Flutter. This layer makes that stream durable so that:

- batches survive our own crashes while the scanner keeps going (the scanner is
  ACK-gated, window 1),
- the app can start search against a local index without rescanning everything,
- future incremental indexing and reconciliation have a stable foundation.

User content never leaves the device; the database stores **metadata only**, never
file bytes.

## 2. Technology

- **Drift** (`drift` + `drift_flutter`) over **SQLite** (`sqlite3_flutter_libs`
  native-assets build). Flutter owns the database; Kotlin never touches it.
- App database name: `vorafind` (native file-backed, `AppDatabase.forApp()`).
- Tests use `NativeDatabase.memory()` — no platform channels involved.

## 3. Schema — `media_items` + `index_state` (v3)

Row type `MediaItem`, generated into `app_database.g.dart`. One row per discovered
file. Ordered fields:

| Column | Type | Notes |
|---|---|---|
| `stable_key` | TEXT PK | `<volumeName>:<mediaStoreId>` — stable, never derived from absolute paths |
| `category` | TEXT | wire `ContentCategory.name` (`images|videos|audio|documents`) |
| `volume_name` | TEXT | MediaStore volume (`external_primary`, `external_sd`, …) |
| `media_store_id` | INT | MediaStore `_ID` |
| `content_uri` | TEXT | `content://…` — the only content access route |
| `display_name` | TEXT | |
| `title` | TEXT? | |
| `mime_type` | TEXT? | |
| `size_bytes` | INT? | |
| `date_added` | INT? | seconds epoch (MediaStore semantics: add/modify) |
| `date_modified` | INT? | |
| `relative_path` | TEXT? | original `RELATIVE_PATH` from the scanner, verbatim |
| `bucket_display_name` | TEXT? | MediaStore bucket label |
| `width` / `height` | INT? | video/image pixel dims |
| `duration_ms` | INT? | video/audio length |
| `artist` / `album` / `album_artist` / `track_number` / `disc_number` / `genre` | TEXT?/INT? | audio metadata; last four are **placeholders** (scanner does not emit them yet) |
| `screenshot_score` | INT? | §17 heuristic score emitted by the scanner |
| `is_screenshot` | INT? (bool) | default `false` |
| `relink_signature` | TEXT? | SHA-256 from the scanner (see §5) — **stored verbatim, never recomputed** |
| `searchable_text` | TEXT | **v3.** normalized keyword-retrieval projection (see `docs/search.md`); derived, durably maintained by the mapper, backfilled for pre-v3 rows |
| `first_discovered_at` / `last_discovered_at` | INT | seconds epoch bookkeeping |
| `last_indexed_generation` | INT? | `generationAfter` of the batch that last wrote the row |
| `metadata_revision` | INT | bumped on every metadata-changing upsert |
| `indexing_status` | TEXT | `IndexingStatus` enum: `none` (fresh) \| `pending` \| `done`; seeded `none`, preserved by upsert |
| `last_seen_access_scope` | TEXT? | `full` \| `partial` of the scan that last saw the row |

### Indexes (why each exists)

- `(category, date_modified)` — future per-category sweeps + "recently modified"
  query plans (architecture §15.2 equivalent).
- `(volume_name, media_store_id)` — idempotency probes during incremental scans.
- `mime_type` — future type filters / extension-family queries.
- `relative_path` — folder browsing + relink debugging.
- `(is_screenshot, category)` — the screenshot-first UX ("I saved a screenshot").
- `last_discovered_at` — future stale-row sweeps for reconciliation.

Declared with Drift `@TableIndex` annotations on the table class; drift emits and
maintains the DDL.

### 3.1 `index_state` — sync checkpoints (v2)

One row per synchronization unit. Row type `IndexState`, generated into
`app_database.g.dart`:

| Column | Type | Notes |
|---|---|---|
| `category` | TEXT | PK, half of the composite key — wire `ContentCategory.name` |
| `volume_name` | TEXT | PK — the MediaStore volume this checkpoint covers |
| `last_generation` | INT? | `getGeneration()` value the unit was last cleanly synced at (API 30+; null below) |
| `access_scope` | TEXT | `full` or `partial` at the time the checkpoint was written |
| `last_sync_at` | INT? | seconds epoch of the last clean sync |

- Composite primary key `(category, volume_name)` — one checkpoint per unit.
- A checkpoint is written **only after a full clean success**; there is no
  mid-batch/mid-run persistence (see §7 bis).

## 4. Identity & Upsert Semantics

- **Stable key** = `volumeName:mediaStoreId`. MediaStore `_ID`s are stable per
  volume until a storage event renumbers them; combined with the volume name this
  is the documented home of identity (`docs/android-discovery.md` §8.1).
- Upsert = `INSERT … ON CONFLICT(stable_key) DO UPDATE`:
  - **INSERT arm** seeds `first_discovered_at = last_discovered_at = now`,
    `metadata_revision = 1`, `indexing_status = none`.
  - **UPDATE arm** refreshes every discovery field + `last_discovered_at`,
    `last_indexed_generation`, `last_seen_access_scope`, and
    `metadata_revision = old + 1`. It **never touches** `stable_key`,
    `first_discovered_at`, or `indexing_status` (respects downstream extraction).
- Idempotent: N scans of the same file ⇒ exactly one row, monotonically newer
  metadata. Sync-level rows (added/modified) are skipped when `sameContent` finds every
  persisted field unchanged (`metadata_revision` only bumps on real changes).
- **No row deletion is ever inferred from a scan's omission under partial scope.**
  Deletion reconciliation runs only for a clean, **full-scope** unit
  (`docs/android-indexing-architecture.md` §9.3); under `partial` a scan adds/updates
  but never deletes.

## 5. What We Store vs. Never Recompute

- `relink_signature` is computed once in Kotlin during discovery
  (SHA-256 of `RELATIVE_PATH|DISPLAY_NAME|SIZE|DATE_MODIFIED`, `null` when there is
  no `RELATIVE_PATH`). The persistence layer treats it as opaque and stores it
  verbatim so relink logic has one source of truth.
- `category` is the wire enum string, preserved for `MediaIndexStats`.

## 6. Discovery → Database → ACK

Source of truth for the wiring: `docs/android-indexing-architecture.md` §13 + this
section. The **only** code that consumes the scanner's batch stream is
`DiscoveryPersistenceOrchestrator` (`lib/core/database/discovery_persistence_orchestrator.dart`).

```
DiscoveryEngine (Kotlin)
  → EventChannel typed batches (window 1)
    → orchestrator: repository.upsertBatch(records)   // one SQLite transaction
        ├─ committed? ─ yes ──▶ ACK batch sequence
        └─ failed?    ────────▶ summary.failed(persistenceFailed); NO ACK
```

- A batch is acknowledged **only after** its SQLite transaction committed — this is
  what makes crash-safe progress possible.
- ACK rejected by the scanner ⇒ run fails loudly (`ackRejected`), committed data is
  retained.
- Scanner terminal events map 1:1: `completed` → success summary, `cancelled` →
  cancelled summary (committed batches stay valid), `error` → failed summary with the
  scanner error.
- Stream ends without a terminal event ⇒ `discoveryInterrupted`; stream throws ⇒
  `discoveryStreamError`. Both fail loudly.
- One transaction per batch. A failed batch rolls back atomically — **no partial
  rows, no ACK**.

## 7. Repository API

`MediaRepository` (interface) / `DriftMediaRepository` (impl) in
`lib/core/database/media_repository.dart`. UI and orchestration depend on the
interface only.

- `upsert(record, {nowSeconds, generationAfter, accessScope})`
- `upsertBatch(records, {…})` → rows written; transactional
- `upsertBatchChanged(records, {…})` → `UpsertBatchDelta {rowsWritten, rowsSkipped}`;
  each row's `sameContent` decides skip vs update — bounds `metadata_revision`
  churn during resyncs
- `fetchByStableKey`, `fetchByStableKeys` → `MediaItem` rows
- `fetchIndexedPage(category, volumeName, {afterId, limit})` → keyset pages of indexed
  rows for (volume, collection), in `media_store_id` order — feeds deletion
  reconciliation
- `count()`, `stats()` → `MediaIndexStats` (total, per-category, distinct volumes)
- `deleteByStableKey(…)` → `bool`; `deleteByStableKeys(keys)` (chunked by caller);
  `clearAll()` (explicit app-level reset only)
- `getSyncCheckpoint(category, volume)` / `saveSyncCheckpoint(category, volume, …)`
  → `SyncCheckpoint?` over `index_state`

`nowSeconds` is injectable for deterministic tests; production uses epoch seconds.

## 7 bis. Synchronization pipeline

```text
SynchronizationCoordinator (Dart)
  ├─ plan: requested categories × their external volumes  (per-unit checkpoints)
  ├─ fast check: checkpoint? + scope full? + getGeneration() == stored → unchanged (skip)
  ├─ else: startDiscovery(category, volumes: filter)  ── per-category sequential session
  │        (fast-pathed volumes are never passed as a filter → never rescanned)
  ├─ per session: shared consumer persists batches (window-1 ACK), lean page buffering
  ├─ finalize unit on clean terminal: DeletionReconciler → saveSyncCheckpoint
  │        (scope full → reconcile deletes + checkpoint(full);
  │         scope partial → upsert only, checkpoint(partial, keeps lastGeneration))
  └─ failed/cancelled unit: reconciler discarded, NO checkpoint written
```

- Per-(category, volume) `index_state` checkpoints, configurable `now`/`generation`
  injection for deterministic tests.
- `DeletionReconciler` (`lib/core/database/deletion_reconciler.dart`) merges
  ascending indexed pages vs the ascending scan ids with bounded memory, and applies
  chunked `DELETE … IN` batches only for rows the scan has already passed.
- Everything runs off the existing method-channel bridge (`startDiscovery` with a
  `volumes` filter, `getGeneration`); no new permissions, no new dependencies.

## 8. Riverpod

`lib/core/database/providers.dart`:

- `databaseProvider` — lazily opens `vorafind`, disposed on ref cleanup.
- `mediaRepositoryProvider` — `DriftMediaRepository` over the shared instance.

The orchestrator is constructed explicitly (tests inject fakes) rather than exposed
as a provider, keeping the persistence seam obvious.

## 9. Migrations

- `schemaVersion = 3`. `onCreate` builds both tables. `onUpgrade`:
  - `from < 2` — adds `index_state` (the only v1→v2 delta; `media_items` DDL is unchanged).
  - `from < 3` — adds `media_items.searchable_text` and backfills existing rows
    with a **paged** sweep (`stable_key` keyset, page size 500) so memory stays
    bounded regardless of library size. Backfill never alters stored metadata,
    only the derived projection; new/extracted rows take the same path via
    `MediaItemMapper`, which maintains `searchable_text` durably on every write.
- The authoritative schema snapshots are committed at
  `drift_schemas/drift_schema_v1.json`, `drift_schema_v2.json`, and
  `drift_schema_v3.json` (generated via `dart run drift_dev schema dump
  lib/core/database/app_database.dart drift_schemas/`).
- Migration tests: fresh install asserts `PRAGMA user_version = 3` + full column
  set (incl. `searchable_text`); an upgrade test crafts an in-place v1 database
  (`DROP TABLE index_state` + `DROP COLUMN searchable_text` + `user_version = 1`
  + a `media_items` row), reopens, and asserts data survived, `index_state` was
  created, `searchable_text` was backfilled, and `user_version == 3`. A second
  upgrade test crafts an in-place v2 database (`DROP COLUMN searchable_text` +
  `user_version = 2`, keeping `index_state`), reopens, and asserts backfill
  fidelity for an audio row's full projection.

## 10. Out of Scope (deferred, do not implement)

`volumes`/`index_errors`/`saf_grants` tables, document (SAF) ingestion, the
N-pass deletion grace period, drift-watcher-based polling, coverage of
`searchable_text` beyond current fields (OCR/text extraction, captions, audio
transcripts; see `docs/search.md`), thumbnails, embeddings, scheduled/WorkManager
indexing. The schema leaves room for these; none are built here.

## 11. Privacy

Database content is metadata for the user's own files, stored only in app-private
SQLite. No analytics, no network calls. `errorMessage` values in run summaries are
user-safe (no file names/paths/content from records).