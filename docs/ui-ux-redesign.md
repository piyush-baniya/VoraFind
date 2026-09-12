# VoraFind UI / UX redesign

This document records *why* the interface is structured the way it is, and the
engineering decisions that keep the redesign honest about the product promise
(privacy-first, local-first, fast, dark-first). It is not a changelog.

## 1. Product shape

The search box is the primary surface. Typing appears above the keyboard at the
bottom of the screen so it never fights the keyboard inset. From the moment the
app opens to the moment results render, the user only ever deals with one
search surface and one set of results.

Navigation is a three-tab shell:

| Tab | Purpose |
|---|---|
| Search (Home) | Search box, active-filter chip, ranked results, discovery fallback |
| Explore | Curated browse views (Recent, Images, Videos, Screenshots, Documents, PDFs, Audio, Large files) |
| Settings | Appearance, indexed-content breakdown, access information, About |

The shell is an `IndexedStack` with a `NavigationBar`. Tabs are built once and
kept alive so switching never re-triggers access checks or loses scroll
position. The three destinations map exactly to the three product verbs users
need: find, browse, configure.

## 2. Themes

Two complete themes (dark and light) are built in `lib/core/theme/`:

- `app_tokens.dart` — spacing, radius, duration and icon-size scale (`VoraSpace`,
  `VoraRadius`, `VoraDuration`, `VoraIconSize`) plus a `reduceMotion` helper
  that reads `MediaQuery.disableAnimations`.
- `app_colors.dart` — the two palettes, exposed to widgets as a `VoraColors`
  `ThemeExtension` (const instances) and a `context.vora` getter. Widgets read
  theme colors only through this extension, never hard-coded hex values.
- `app_typography.dart` — one shared text-style pipeline, varied per brightness.
- `app_theme.dart` — `AppTheme.dark()` / `AppTheme.light()`: complete component
  theming (navigation bar, chips, inputs, lists, surfaces, sheets), seeded from
  the same design tokens so both modes stay consistent.

The active mode is `ThemeMode.system | light | dark`, chosen in Settings and
persisted **from the app itself** in the Drift `app_settings` table (schema v9,
see `lib/core/settings/`). Dark is the default. Persisting in Drift instead of
adding a settings package keeps the dependency surface small and reuses the
database the app already owns.

The theme-preference provider (`themePreferenceProvider`) loads the stored
value asynchronously (microtask) so the first frame renders synchronously in
dark without a theme flash.

## 3. Shared widget library

`lib/features/shared/widgets/` holds the reusable pieces so every screen cannot
drift into its own bespoke visuals:

- `vora_search_bar.dart` — the only search box in the app. Controlled text
  field with focus-triggered border animation, a clear button that only appears
  while text exists, and a filter sheet (`RadioGroup` single-type selection)
  that feeds the persistent `searchResultsProvider` query.
- `vora_result_tile.dart` — one result-row contract for every screen:
  thumbnail, title, metadata line, match-explanation pill, and the
  similar-image affordance. Includes `VoraResultList` (infinite lazy list with
  the Flow/Bottom growing-row flow) and `VoraGridCard` (square-tile grid).
- `vora_thumbnail.dart` — async thumbnail presenter: placeholder, spinner,
  graceful fallback when a thumbnail cannot load. Nothing blocks the UI thread.
- `vora_image_cache.dart` — bounded LRU byte cache over the platform
  `ImagePixelSource`, shared via `voraImageCacheProvider`. In-flight requests
  are deduplicated. Bounded cache is essential: thumbnail generation reads
  platform pixels and a leak would otherwise grow without limit while the user
  scrolls.
- `vora_surfaces.dart` — empty states, loading views, section headers and
  settings rows with a consistent layout.

## 4. Home screen states

The Home screen is honest about pipeline state:

- **Index empty** → onboarding card with a single "Give access" action. No
  pretend results. The action requests image access and starts indexing.
- **Indexing in progress** → a status tile with a real fraction when the
  pipeline reports one; retry/resume when a phase failed. It is hidden when
  idle (an invisible spinner would be dishonest).
- **No query yet** → discovery fallback (Recent grid + occasional similar-image
  picker from known-recent images) so the app is never a blank rectangle.
- **Results** → ranked `VoraResultList`. **No matches** → an empty state, not
  a spinner.

Search itself runs through the *existing* bounded retrieval pipeline
(`searchServiceProvider` under `searchResultsProvider`, 200 ms debounce). The
UI never bypasses ranking.

## 5. Explore

`lib/core/search/explore_providers.dart` reuses the retrieval pipeline: each
filter is a `SearchQuery` with a category constraint (or a `largeFiles`
threshold) and no keyword, and results are ranked exactly like typing. There is
no second browse path, so browse results and search results can never disagree
in mechanism.

Image-heavy filters render as a square grid (lazy `SliverGrid`); everything
else reuses `VoraResultList`. Screenshots are an explicit filter for phone-save
habits, separate from plain Images.

## 6. Settings screen

Settings reads live provider state — never fabricated rows:

- Appearance: System default / Light / Dark radios bound to
  `themePreferenceProvider`.
- Indexed content: real rows from `indexStatsProvider` (images, videos, audio)
  and `documentStatsProvider` (documents), each with counts.
- Access readout: a live per-category state string (full / partial / denied /
  none) derived from the platform's `ContentCapabilities` — access is never
  assumed from what the app *typed*.
- About: brand block, version, and Privacy Policy / Terms / Open source
  licenses pushed from local routes. Model licenses are registered in
  `main.dart` (MobileNetV2 from ONNX Model Zoo, all-MiniLM-L6-v2, both
  Apache-2.0) and shown via `showLicensePage` — no other attribution screen is
  needed because nothing else ships model weights.

## 7. Motion and accessibility

- Animations are 150–250 ms and serve state (focus border, tab switching,
  results swapping via `AnimatedSwitcher`). Nothing expensive animates on every
  frame.
- `reduceMotion` collapses decorative transitions when the OS requests reduced
  motion.
- Text scales with the platform; every touch target keeps Material minimum
  sizes; search results explain *why* they matched (label pills like `Matched
  in OCR`) instead of showing unexplained scores.

## 8. Performance rules the UI obeys

- Thumbnails and pixels load asynchronously through the bounded cache; the UI
  thread never reads platform pixels.
- Result lists and grids are lazy; nothing builds thousands of rows eagerly.
- The browse/search pipelines are the project's existing bounded queries with
  limits; the UI never triggers full-library scans.
- The widget layer stays thin: big hits keep rendering cheap so jank stays low
  even while embedding/OCR/indexing run in the background.