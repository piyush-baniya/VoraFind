# VoraFind — Product Requirements Document

**Product:** VoraFind
**Version:** 0.1 MVP
**Platform:** Android first
**Framework:** Flutter
**Primary goal:** Build the fastest, most useful, privacy-first search engine for content a user has saved on their phone.

---

# 1. Product Vision

VoraFind is a personal search engine for a user's own device.

Instead of forcing users to remember:

* the filename,
* which folder something is in,
* when they saved it,
* whether it was a screenshot, photo, PDF, or document,

VoraFind should let them simply describe what they are looking for.

Examples:

> "Find the screenshot of the laptop I wanted to buy."

> "Show me the PDF about Flutter architecture."

> "Find the image containing a phone number I saved."

> "Find the document I downloaded last month."

> "Show me screenshots containing RTX 5050."

The application should turn the user's device into a searchable personal information space.

---

# 2. Core Product Promise

## "Find anything you've saved on your phone."

The experience should feel:

* fast,
* accurate,
* simple,
* private,
* intelligent,
* reliable,
* modern.

The user should not need to understand how indexing, OCR, databases, embeddings, or search ranking work.

Those are implementation details.

The product should simply help the user find things.

---

# 3. Product Principles

## 3.1 Privacy First

User content stays on the device by default.

VoraFind should not upload personal files, photos, screenshots, documents, or extracted content to a server for normal search functionality.

No account should be required.

No cloud backend should be required for the MVP.

---

## 3.2 Offline First

Core functionality must work without an internet connection.

The following should work offline:

* indexing,
* searching,
* filtering,
* browsing results,
* opening files,
* OCR where the selected local OCR implementation supports it,
* metadata extraction,
* duplicate detection.

Internet access must never be a requirement for basic device search.

---

## 3.3 Accuracy Over Flashiness

A beautiful interface is important, but search quality is more important.

Do not add AI features merely because they sound impressive.

Every intelligent feature must provide measurable user value.

---

## 3.4 Fast by Design

VoraFind must be designed for large personal libraries.

The architecture should target devices containing:

* tens of thousands of images,
* thousands of screenshots,
* thousands of documents,
* large media libraries.

Search should not require rescanning the entire device every time.

Indexing should be incremental and resumable.

---

## 3.5 Simple UX

The application should not have a confusing navigation structure.

The primary experience should revolve around one obvious action:

**Search.**

Users should be able to open the app and immediately search.

---

# 4. Target Users

VoraFind is intended for people who accumulate large amounts of personal digital content.

Examples:

* students,
* developers,
* professionals,
* researchers,
* content creators,
* people who frequently take screenshots,
* people who download many documents,
* people who save reference images,
* people with large photo/document collections.

---

# 5. MVP Scope

The MVP should establish the core search engine.

## Included in MVP

### Device indexing

Index supported content stored on the device.

Initial supported categories:

* Images
* Screenshots
* PDFs
* Text documents where practical
* Basic video metadata
* Basic audio metadata
* File metadata

---

# 6. Indexed Information

VoraFind should extract and index as much useful searchable information as practical.

## 6.1 File metadata

Examples:

* filename
* extension
* MIME type
* file size
* creation date where available
* modification date
* path/location where available
* media type
* duration for supported media
* dimensions for images/videos
* artist/album/title for supported audio

---

## 6.2 Image information

For supported images:

* filename
* metadata
* dimensions
* dates
* location metadata where available and permitted
* OCR text
* searchable visual information where implemented

Screenshots should receive special attention because they are often information-heavy.

---

## 6.3 OCR

VoraFind should be able to search text visible inside supported images.

Examples:

A screenshot contains:

> "RTX 5050 Laptop"

Searching:

> `RTX 5050`

should be capable of returning that screenshot.

OCR should be performed locally whenever practical.

OCR processing must not block the UI.

---

## 6.4 PDF/document text

Where technically practical, extract searchable text from supported documents.

The extracted text should be indexed locally.

The original file must remain untouched.

---

# 7. Search Engine

Search is the most important component of VoraFind.

The search system should evolve toward a hybrid architecture.

## 7.1 Exact search

Search:

`IMG_1234`

should find matching filenames.

---

## 7.2 Keyword search

Search:

`RTX 5050`

should match:

* filenames,
* OCR text,
* document text,
* metadata,
* tags where applicable.

---

## 7.3 Natural-language search

Users should eventually be able to write:

> "Find the screenshot of the laptop I was researching."

The system should combine available signals rather than depending on one search method.

---

## 7.4 Hybrid search

The long-term search architecture should combine:

* lexical/keyword search,
* metadata matching,
* OCR matching,
* semantic search,
* optional visual understanding,
* temporal signals,
* file relationships.

The architecture should allow these components to be added independently.

Do not build an unnecessarily complicated vector system before it provides value.

---

# 8. Search Ranking

Search results should be ranked rather than simply returned in arbitrary order.

Potential ranking signals include:

* exact filename match,
* exact OCR match,
* keyword frequency,
* semantic similarity,
* file type,
* recency,
* metadata match,
* search term position,
* user interaction history where privacy-safe,
* query intent,
* content relevance.

Ranking should be deterministic and explainable where practical.

---

# 9. Search Result UX

Each result should communicate enough information for the user to recognize it immediately.

Potential result information:

* thumbnail/icon,
* filename,
* file type,
* date,
* location/folder where appropriate,
* relevant extracted text,
* reason for match.

Example:

**Laptop Screenshot**

`RTX 5050 • 16GB RAM`

`Screenshots • Aug 2026`

The UI should avoid unnecessary information overload.

---

# 10. Search Filters

Users should eventually be able to filter results by:

* file type,
* date,
* date range,
* folder/location,
* file size,
* image/video/audio/document,
* screenshots,
* favorites/collections where implemented.

Filters should be secondary to the main search experience.

---

# 11. Indexing Architecture

Indexing must be designed as a background, incremental process.

## Initial indexing

When VoraFind first receives appropriate access:

1. Discover supported files.
2. Read metadata.
3. Store searchable metadata.
4. Process supported content.
5. Run OCR where appropriate.
6. Update the local index.
7. Continue until complete.
8. Persist progress continuously.

---

## Incremental indexing

After initial indexing, VoraFind should avoid unnecessarily processing unchanged files.

The system should detect:

* new files,
* modified files,
* deleted files,
* moved files where detectable.

Only affected content should be reprocessed.

---

## Resumable indexing

If indexing is interrupted because:

* the application closes,
* the device restarts,
* the user pauses indexing,
* Android stops background work,

the indexer should resume safely.

It must not restart the entire indexing process unnecessarily.

---

# 12. Performance Requirements

Performance is a core product requirement.

## Search

Normal local searches should feel nearly instantaneous once the relevant index exists.

Avoid performing expensive full-library scans during normal searches.

---

## Indexing

Indexing should:

* use batches,
* avoid excessive memory usage,
* avoid blocking the UI thread,
* support cancellation,
* support resumption,
* avoid unnecessary duplicate processing,
* be battery-conscious.

---

## Large libraries

The architecture should be designed with large libraries in mind.

The MVP should not assume that a user only has a few hundred files.

---

# 13. UI / UX Direction

VoraFind should have a premium modern interface.

## Design language

Preferred characteristics:

* dark-first,
* AMOLED-friendly,
* clean,
* minimal,
* modern,
* smooth,
* responsive,
* accessible.

The design should not become excessively purple or overly decorated.

Use color primarily for:

* important actions,
* selection,
* status,
* hierarchy,
* subtle branding.

Avoid excessive:

* gradients,
* glowing borders,
* unnecessary animations,
* giant cards,
* decorative UI,
* complicated navigation.

---

# 14. Primary App Experience

The home screen should prioritize search.

Possible structure:

### Home

* VoraFind branding
* prominent search field
* recent searches
* indexing status when relevant
* quick filters/categories
* recently found/recently indexed content where useful

The user should understand the application immediately.

---

# 15. Search Experience

The search interface should feel responsive.

Expected behavior:

1. User taps search.
2. User types a query.
3. Results appear progressively when practical.
4. Results are ranked.
5. User can filter.
6. User can open the original content.

The interface should clearly communicate when indexing is incomplete.

---

# 16. File Actions

From a result, the user should be able to:

* open the original file,
* share it,
* view details,
* optionally favorite/save it,
* access the original location where supported.

VoraFind should never replace or modify the user's original files without explicit user action.

---

# 17. Index Status

Users should be able to understand:

* whether indexing is running,
* whether indexing is paused,
* how much has been indexed,
* whether processing is incomplete,
* whether additional permissions are needed.

Avoid technical terminology where possible.

Instead of:

> "SQLite FTS indexing queue: 82%"

Prefer:

> "Preparing your library… 82%"

---

# 18. Permissions

Permissions must follow Android and Google Play requirements.

VoraFind should request only permissions genuinely required for its core functionality.

Do not automatically request:

* contacts,
* SMS,
* call logs,
* microphone,
* location,
* camera,
* broad storage access,

unless a future feature genuinely requires them.

Do not use `MANAGE_EXTERNAL_STORAGE` unless there is an unavoidable, policy-compliant core requirement.

The permission architecture must be designed with Google Play's current policies in mind.

---

# 19. Privacy Controls

The user should eventually be able to control:

* what content is indexed,
* whether specific folders are excluded,
* whether indexing is paused,
* whether the index can be rebuilt,
* whether indexed data can be deleted.

The application should clearly explain that search indexes are derived from user content and are stored locally.

---

# 20. No Account Requirement

The MVP should not require:

* account creation,
* login,
* email,
* cloud synchronization.

VoraFind should work immediately after installation and appropriate permission/access setup.

---

# 21. Share Sheet Integration

A future MVP/early post-MVP feature should allow:

**Share → VoraFind**

The shared content can be indexed or added to a personal collection.

This provides a fast way for users to intentionally save content into VoraFind.

---

# 22. Duplicate Detection

A duplicate detection foundation should be considered during the architecture design.

Potential capabilities:

* exact duplicates,
* near-duplicate images,
* duplicate documents,
* storage savings insights.

Do not allow duplicate detection to complicate the core search engine prematurely.

---

# 23. Future AI Features

AI should enhance the search engine rather than replace it.

Potential future features:

## Ask VoraFind

Users could ask:

> "What was the laptop I was researching?"

VoraFind could answer using locally indexed information.

---

## Semantic search

Example:

Search:

> "laptop I wanted for gaming"

could find content mentioning:

* gaming laptop,
* RTX 5050,
* GPU,
* laptop specifications.

---

## Related content

A result could show:

> "Related items"

based on semantic or contextual relationships.

---

## Smart collections

Examples:

* Study
* Shopping
* Work
* Projects
* Travel
* Screenshots

These should be generated only when they provide genuine value.

---

# 24. Long-Term Personal Memory

A future direction is to turn VoraFind into a private personal information layer.

Potential searchable information:

* saved files,
* screenshots,
* documents,
* notes,
* shared content,
* voice notes,
* selected images,
* timelines,
* relationships between content.

The goal is not to build a generic chatbot.

The goal is:

**"Your personal information, searchable."**

---

# 25. Face / People Search

A future local-only feature could optionally allow users to organize/search their own photo collections by people.

This must be:

* opt-in,
* local-first,
* privacy-conscious,
* clearly explained.

VoraFind must not be designed around identifying strangers from public photos or crawling social media for people's identities.

---

# 26. Explicit Non-Goals

VoraFind MVP must NOT become:

* an internet-wide search engine,
* a social-media crawler,
* a stranger-identification system,
* a public facial-recognition search engine,
* a cloud file backup service,
* a generic AI chatbot,
* a social network,
* a private-message monitoring tool,
* an SMS indexing application,
* a contact-monitoring application.

These are outside the core product.

---

# 27. Architecture Direction

Preferred technology direction:

* Flutter
* Dart
* Riverpod where state management requires it
* Drift/SQLite for local structured data
* Android native Kotlin where platform APIs are required
* MediaStore where appropriate
* native/platform bridges for expensive device operations
* local search indexes
* local OCR
* optional local AI later

Flutter should own the application UI and orchestration.

Platform-specific code should handle operations where Android APIs provide substantially better performance or access.

---

# 28. Database Direction

The local database may eventually contain concepts such as:

* files
* media metadata
* OCR text
* document text
* index state
* search metadata
* tags
* collections
* relationships
* processing state

The exact schema must be determined from actual implementation requirements.

Do not create dozens of speculative tables simply because they appear in this PRD.

---

# 29. Dependency Philosophy

Dependencies should be kept intentionally small.

Before adding a package, ask:

1. Is it genuinely required?
2. Is Flutter/Dart insufficient?
3. Is the package maintained?
4. Does it affect application size?
5. Does it affect performance?
6. Does it create privacy/security concerns?
7. Can a small native implementation do the job better?

Avoid dependency bloat.

---

# 30. Reliability Requirements

VoraFind must behave safely when:

* files are deleted externally,
* files are moved,
* permissions change,
* indexing is interrupted,
* storage becomes unavailable,
* OCR fails,
* a document cannot be parsed,
* an individual file is corrupted,
* Android kills background work.

One problematic file must not break the entire index.

Errors should be isolated and recoverable.

---

# 31. Battery and Resource Requirements

Background processing must be conservative.

Avoid:

* continuous unnecessary scanning,
* repeated OCR,
* repeated thumbnail generation,
* large memory allocations,
* unnecessary CPU-heavy operations.

Processing should happen in controlled batches.

---

# 32. Accessibility

The UI should support:

* readable text,
* sufficient contrast,
* touch-friendly controls,
* screen readers where practical,
* meaningful semantic labels,
* scalable text.

Do not sacrifice accessibility for visual effects.

---

# 33. Analytics and Privacy

The MVP should avoid collecting personal content for analytics.

Do not send:

* file contents,
* OCR text,
* filenames containing personal information,
* private images,
* document contents,

to external analytics services.

If analytics are introduced later, they must be privacy-conscious and separately evaluated.

---

# 34. Monetization

The MVP can initially be free.

Possible future monetization:

### VoraFind Free

Core:

* device indexing,
* search,
* OCR,
* filters,
* basic organization.

### VoraFind Plus

Potential advanced features:

* advanced local AI,
* larger models,
* advanced semantic search,
* advanced visual search,
* advanced duplicate detection,
* advanced automation.

Core search should remain useful without payment.

Do not introduce monetization until the product provides real value.

---

# 35. Development Phases

## Phase 0 — Foundation

* Flutter project
* architecture
* project configuration
* design system foundation
* navigation shell
* testing foundation
* documentation

---

## Phase 1 — Device Indexing

* Android MediaStore integration
* file discovery
* metadata extraction
* local database
* index state
* background processing
* incremental updates

---

## Phase 2 — Basic Search

* keyword search
* filename search
* metadata search
* ranking
* filters
* result UI

---

## Phase 3 — Content Search

* OCR
* PDF text extraction
* document text extraction
* screenshot search
* richer result previews

---

## Phase 4 — Search Quality

* improved ranking
* query normalization
* fuzzy matching
* relevance scoring
* search suggestions
* search history

---

## Phase 5 — Semantic Search

* embeddings
* local vector search where justified
* hybrid lexical + semantic search
* natural-language queries

---

## Phase 6 — Intelligent Features

* Ask VoraFind
* related content
* smart collections
* contextual search
* local AI features

---

## Phase 7 — Advanced Features

Potential:

* duplicate detection
* timeline
* people/face organization
* visual search
* voice search
* Share Sheet workflows
* deeper personal memory

---

# 36. North-Star Query

The product architecture should eventually be capable of answering a query such as:

> "Find the screenshot of the laptop I was researching around the time I was looking at RTX 5050 laptops."

This could require:

* OCR,
* filename matching,
* image understanding,
* semantic search,
* dates,
* metadata,
* ranking,
* related content.

This represents the long-term direction of VoraFind.

---

# 37. Definition of Success

VoraFind succeeds when a user can think:

> "I know I saved it somewhere."

…and VoraFind can find it quickly.

The application should reduce the cognitive burden of remembering:

* filenames,
* folders,
* dates,
* where something was saved.

The best version of VoraFind should feel less like a file manager and more like a personal search engine.

---

# 38. MVP Quality Bar

Before calling the MVP complete:

* Search must be fast.
* Indexing must be reliable.
* Indexing must resume safely.
* Search must work offline.
* UI must remain responsive during indexing.
* Large libraries must not cause obvious instability.
* Errors from individual files must be isolated.
* Permissions must be justified and minimal.
* No unnecessary backend should exist.
* No unnecessary dependencies should exist.
* No secrets should be committed.
* Core functionality must be testable.
* The UI must be simple enough for a first-time user to understand immediately.

---

# 39. Final Product Principle

Do not build VoraFind as:

**"an AI app that happens to search files."**

Build it as:

**"the best personal search engine for everything you've saved on your phone."**

AI is a tool.

Search quality is the product.
