# VoraFind — Android Permission & Capability Layer

## 1. Purpose and scope

This layer answers three questions Flutter needs before any discovery runs:

1. **Can this device grant VoraFind access to each media collection?** — the
   capability snapshot (`ContentCapabilities`).
2. **Where does access stand right now?** — a side-effect-free state query per
   category (`images`, `videos`, `audio`, `documents`).
3. **How does a user grant access?** — runtime media permission requests and the
   Storage Access Framework (SAF) folder picker.

It is a thin, typed foundation. It does **not** enumerate files, build an index,
or persist anything.

## 2. Scope boundaries

This layer deliberately does **not** implement:

* MediaStore/SAF enumeration or scanning (future discovery phase),
* any database/index (future Drift phase),
* background work, services, or foreground services,
* any UI — Flutter owns all screens and flows,
* `MANAGE_EXTERNAL_STORAGE`, write, location, contacts, or phone permissions.

It only adds read permissions that are narrowly tied to the media collections
VoraFind searches. No runtime dependency was introduced; the native side uses the
platform Activity Result API and manifest-declared permissions only.

## 3. Architecture

```text
Flutter (Dart)
   │  MethodChannel "vorafind/content_access"
   ▼
ContentAccessBridge (Kotlin)          ← dispatches the six callable methods
   ├── MediaPermissionService         ← permission state + Activity Result request
   ├── DocumentAccessService          ← SAF picker + persisted URI permission grants
   └── ContentCapabilityService       ← one-shot capability snapshot
       └── CapabilityMapper           ← pure: capability/access derivation
       └── AccessStateMapper          ← pure: permission flags → ContentAccessState
       └── ContentAccessState/Category ← pure: enums + wire mapping
```

The two pure layers (`AccessStateMapper`, `CapabilityMapper`, the enums, and the
per-category permission policy in `permissionsFor`) are JVM unit tests without a
device. `MainActivity` extends `FlutterFragmentActivity` and only wires the bridge
into the Dart executor; it contains no permission/SAF logic.

## 4. Contract

Channel: `vorafind/content_access`. Payloads are plain maps; enum wire values are
identical strings in Kotlin and Dart.

Allowed categories (`ContentCategory`): `images`, `videos`, `audio`, `documents`.

States (`ContentAccessState`):

| Wire value | Meaning |
| --- | --- |
| `notRequired` | No permission applies on this platform/API level |
| `noAccess` | Not granted, not yet denied (request is possible) |
| `denied` | Explicitly denied, can ask again |
| `permanentlyDenied` | Denied and cannot be requested again (must go to settings) |
| `fullAccess` | Full media library readable |
| `partialAccess` | Only a user-selected subset readable (SAF folder or Android 14+ partial media) |

Methods:

| Method | Args | Returns |
| --- | --- | --- |
| `getCapabilities` | — | `{contractVersion, platform, apiLevel, safCapable, mediaStoreGenerationSupported, partialMediaAccessSupported, externalVolumes, categories[]}` |
| `getPermissionState` | `{category}` | `{category, state, canQuery, canReadAll, canReadSelected}` |
| `requestMediaAccess` | `{category}` | same shape as `getPermissionState`; rejects `documents` with code `invalidArguments` |
| `requestDocumentTree` | — | `{cancelled, grant{uri, displayName, persisted, readable, writable}}` |
| `listDocumentTreeGrants` | — | `[{uri, displayName, persisted, readable, writable}]` |
| `releaseDocumentTreeGrant` | `{uri}` | `bool` |

Error codes: `invalidArguments`, `pickUnavailable`, `grantFailed`,
`permissionRequestFailed`, `security`, `unknown`. On the Dart side these map to a
typed `ContentAccessException`; a `PlatformException` is never surfaced raw.

The access flags (`canQuery`, `canReadAll`, `canReadSelected`) are **derived from
`state`** on both sides of the bridge and the wire carries only the winning state,
so a partial grant can never be misreported as full access.

## 5. Permission strategy per API level

| API | Images | Videos | Audio |
| --- | --- | --- | --- |
| 24–32 | `READ_EXTERNAL_STORAGE` (one permission covers all media) | same | same |
| 33+ | `READ_MEDIA_IMAGES` | `READ_MEDIA_VIDEO` | `READ_MEDIA_AUDIO` |

Manifest additions (read-only, narrowly scoped):

* `READ_EXTERNAL_STORAGE` with `maxSdkVersion="32"`,
* `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`,
* `READ_MEDIA_VISUAL_USER_SELECTED` — **declared but never requested** by the app;
  the OS grants it automatically when a user picks specific items on Android 14+.

No write permission is requested or declared. On API 34+ a user may answer the
visual-media request with *selected items*; the OS then grants
`READ_MEDIA_VISUAL_USER_SELECTED` instead of `READ_MEDIA_IMAGES/VIDEO`.

## 6. Partial access semantics

A partial grant is possible in two places:

* **SAF folder picker** — the grant covers one folder tree, always partial.
* **Android 14+ visual media request** — the grant covers only selected items.

**Policy: partial must never be treated as full.**

* `canReadAll == true` **only** for `fullAccess`.
* `canReadSelected == true` only for `partialAccess`.
* `canQuery == true` for `full`/`partial`/`notRequired` — VoraFind may query,
  but discovery must reason per-item about whether each row was selected.

Documents never reach `fullAccess`: folders are always scoped, so the documents
capability reports `notRequired`, `noAccess`, or `partialAccess` only. The future
discovery engine will preserve this distinction by tracking per-row visibility
(e.g. MediaStore-generated selection columns / SAF document IDs) rather than
collapsing partial grants into "everything readable" queries.

## 7. SAF strategy

* `requestDocumentTree` launches `ACTION_OPEN_DOCUMENT_TREE` with read +
  persistable flags.
* On success, `takePersistableUriPermission(read)` is applied **eagerly** so the
  grant survives app restarts, and a `DocumentGrant` (URI, display name, read
  flags) is returned for the Flutter layer to present.
* Grant **persistence itself is owned by Android**. The Dart side may later persist
  `DocumentGrant` as metadata in Drift, but the authoritative grant remains the
  OS-managed `persistedUriPermissions` set; `listDocumentTreeGrants` always reads
  from the truth so externally revoked grants disappear automatically.
* Only **read** flags are used on the grant/flags and in `releaseDocumentTreeGrant`.
* Cancel yields `{cancelled: true, grant: null}` — never an error.
* Unavailable pickers / exceptions map to `pickUnavailable`.

## 8. Privacy and data flow

* Permission state and capabilities are read directly from the platform in memory;
  nothing is written to disk by this layer.
* The Dart facade never receives raw `PlatformException` internals — only
  typed codes and short messages.
* No user file content crosses this layer: no filenames are enumerated, no
  thumbnails, no OCR, no MediaStore rows.
* No analytics, no network: there is no outbound data path in this feature.

## 9. Testing strategy

* **Kotlin JVM unit tests** (`android/app/src/test/java/...`):
  * `AccessStateMapperTest` — state mapping, including that partial selection
    never collapses to full access,
  * `CapabilityMapperTest` — capability payload contract, API-level thresholds,
    flag derivation, category ordering,
  * `MediaRequestPolicyTest` — the per-API permission matrix, documents-reject,
  * `DocumentGrantTest` — grant fields and bridge map shape.
* **Dart unit tests** (`test/content_access_models_test.dart`,
  `test/content_access_facade_test.dart`): wire parsing, flag derivation, channel
  argument/response correctness against a mocked `MethodChannel`, and typed
  exception mapping.
* **Device-level behavior** (permission dialogs, SAF picker, partial selection)
  is validated manually on-emulator/on-device; the JVM test harness cannot
  exercise the Activity Result path.

## 10. Known limitations and risks

* **`registerForActivityResult` coupling:** the services must be constructed with a
  live `Activity`. Activity Result launches are process-activity bound; if the
  activity is recreated while a permission/picker result is pending, the Dart
  future may never resolve. Mitigated by the manifest `configChanges` declaration,
  which prevents most recreation during this flow.
* **"Don't ask again" detection:** `shouldShowRequestPermissionRationale` is the
  only portable signal; on some OEMs it is reliable, on others approximate. The
  state model still degrades gracefully to `permanentlyDenied` / settings intent
  later rather than stalling.
* **JVM tests stub Android (`android.jar`):** only the pure Kotlin logic is unit
  tested; every `android.*` call in the services is device-tested instead.
* **Not yet implemented:** settings redirection, user doc of partial access, and
  any UI.

## 11. Evolution

* **Discovery contract:** the `vorafind/indexing` channel in the architecture doc
  remains the surface for enumeration. This layer stays permission/capability-only;
  do not grow it into a scanner.
* **Pigeon:** if the six-method surface grows beyond ~10 methods, migrate the
  facade + bridge to generated typed bindings. Not done now (no dependency bloat).
* **Data-dependent features:** `mediaStoreGenerationSupported` (API 30+) and
  `partialMediaAccessSupported` (API 34+) are already surfaced so the future
  discovery phase can choose generation-based incremental scans and per-item
  selection handling without renegotiating permissions.