# VoraFind — Agent Instructions

## 1. Mission

You are working on **VoraFind**, a privacy-first personal search engine for Android.

The product promise is:

> **Find anything you've saved on your phone.**

Before implementing anything, read:

* `PRD.md`
* `README.md`
* the existing source code
* relevant tests
* relevant platform code

`PRD.md` defines **WHAT** VoraFind should become.

This file defines **HOW** the coding agent must work.

---

# 2. Source of Truth

Never assume that a feature is implemented simply because it appears in `PRD.md`.

The repository's actual code is the source of truth for implementation state.

Before changing anything:

1. Inspect the repository.
2. Identify the existing implementation.
3. Identify dependencies and architecture.
4. Identify existing tests.
5. Determine the smallest correct change.
6. Implement.
7. Test.
8. Review the diff.

Do not recreate functionality that already exists.

Do not replace working architecture without a concrete reason.

---

# 3. Product Priorities

Always prioritize in this order:

1. Correctness
2. Search accuracy
3. Reliability
4. Performance
5. Privacy
6. Maintainability
7. UX simplicity
8. Visual polish
9. Additional features

A flashy feature that makes the core product less reliable is not acceptable.

---

# 4. Core Engineering Philosophy

VoraFind must be:

* local-first,
* offline-first,
* fast,
* accurate,
* resilient,
* privacy-conscious,
* maintainable,
* easy to use.

The application should be designed for large personal libraries.

Do not optimize only for a test device containing a few hundred files.

---

# 5. Flutter Standards

Use:

* Dart null safety.
* Modern Flutter APIs.
* Clear separation of UI and business logic.
* Small, focused widgets.
* Immutable state where practical.
* Strong typing.
* Explicit error handling.

Avoid:

* unnecessary global state,
* giant widgets,
* deeply nested widget trees where avoidable,
* magic numbers,
* duplicated business logic,
* dead code,
* speculative abstractions.

---

# 6. Architecture

Use a clean, pragmatic architecture.

Do not create excessive layers simply to make the project look "enterprise."

A reasonable direction is:

```text
Presentation
    ↓
Application / State
    ↓
Domain / Use Cases where justified
    ↓
Data
    ↓
Platform / Storage
```

Use Riverpod where application state requires it.

Use Drift/SQLite for structured local persistence where appropriate.

Use native Android Kotlin when Android platform APIs or performance requirements make it the correct choice.

Flutter should own the UI.

---

# 7. Android Platform Strategy

Android is the first target platform.

Use Android platform APIs where they provide the correct access or performance.

Potential platform responsibilities include:

* MediaStore discovery,
* device file/media metadata,
* Android-specific background processing,
* platform permissions,
* native performance-heavy operations.

Keep the Flutter/native bridge:

* small,
* typed,
* documented,
* resilient to errors.

Do not move large amounts of application business logic into Kotlin without a reason.

---

# 8. Privacy Rules

Privacy is a fundamental product requirement.

Do not:

* upload user files without explicit product requirements,
* upload OCR text,
* upload private images,
* upload document contents,
* introduce a cloud backend without explicit approval,
* add analytics that collect personal content,
* expose user content to third-party services without explicit approval.

The default architecture should assume:

> **User content stays on the device.**

---

# 9. Permissions

Request only permissions genuinely required by the current feature.

Do not add permissions speculatively.

Never add:

* `MANAGE_EXTERNAL_STORAGE`
* contacts permissions
* SMS permissions
* call-log permissions
* microphone permissions
* location permissions

unless a specific approved feature requires them and the permission is appropriate under current Google Play policy.

For every new permission, explain:

* why it is needed,
* which feature requires it,
* whether a narrower API exists,
* whether it affects Google Play compliance.

---

# 10. No Internet by Default

The MVP must not depend on a backend.

Do not add:

* Firebase,
* Supabase,
* Appwrite,
* custom servers,
* cloud databases,
* external AI APIs,

unless explicitly requested and reviewed.

Internet access should not be assumed to be available.

Core search must continue working offline.

---

# 11. Dependency Rules

Before adding a package:

1. Confirm that it solves a real requirement.
2. Check whether Flutter/Dart already provides the capability.
3. Check whether a small native implementation is more appropriate.
4. Consider package maintenance.
5. Consider APK size.
6. Consider startup cost.
7. Consider runtime performance.
8. Consider privacy/security implications.

Avoid dependency bloat.

Do not add packages just because they are popular.

Do not add multiple packages solving the same problem.

---

# 12. Performance Rules

Performance is a first-class requirement.

Never perform expensive operations directly on the UI thread.

Be particularly careful with:

* filesystem scanning,
* MediaStore queries,
* OCR,
* document parsing,
* thumbnail generation,
* embeddings,
* vector operations,
* large database operations.

Use:

* batching,
* isolates/background execution where appropriate,
* pagination,
* incremental processing,
* caching,
* database indexes,
* cancellation,
* resumable processing.

Do not repeatedly scan the entire library for normal searches.

---

# 13. Indexing Rules

The indexer must be designed as a reliable pipeline.

It should support:

* initial indexing,
* incremental indexing,
* resumability,
* cancellation,
* retries,
* failure isolation,
* deletion detection,
* modification detection.

One corrupt or unsupported file must not stop the entire indexing process.

Persist progress safely.

Avoid keeping the entire library in memory.

---

# 14. Search Rules

Search is the core feature.

Do not implement search as repeated full-library scans.

The architecture should allow:

* exact matching,
* keyword matching,
* OCR matching,
* metadata matching,
* fuzzy matching,
* semantic matching later.

Ranking should be deterministic and testable.

When implementing ranking, document why each ranking signal exists.

Do not introduce embeddings/vector search simply because it sounds more advanced.

Use them when they demonstrably improve search quality.

---

# 15. AI Rules

AI is optional infrastructure, not the product itself.

Do not add:

* generic chatbot screens,
* unnecessary AI-generated content,
* cloud AI APIs,
* large models,

without an explicit requirement.

When AI is eventually introduced:

* prefer local/on-device processing,
* measure actual usefulness,
* keep deterministic search available,
* never make basic search dependent on AI.

---

# 16. UI/UX Rules

The interface should be:

* modern,
* clean,
* minimal,
* dark-first,
* smooth,
* responsive,
* accessible.

Avoid:

* excessive gradients,
* excessive purple,
* glowing borders,
* unnecessary animations,
* excessive cards,
* complicated navigation,
* decorative elements that reduce usability.

Animations must serve UX.

Never animate expensive operations unnecessarily.

---

# 17. Search UX Rules

The search box is the primary interaction.

Users should be able to understand the application without a tutorial.

Search results should provide useful context without overwhelming the user.

Where practical, explain why an item matched.

Example:

```text
Matched in OCR
"RTX 5050"
```

This is preferable to showing an unexplained relevance score.

---

# 18. State Management

Keep state ownership clear.

Avoid:

* duplicated state,
* state hidden inside unrelated widgets,
* unnecessary providers,
* circular dependencies.

Long-running operations such as indexing must have explicit states such as:

```text
idle
running
paused
completed
failed
```

The UI must react predictably to state changes.

---

# 19. Error Handling

Never silently swallow important errors.

Errors should:

* be logged appropriately for development,
* provide useful context,
* avoid exposing sensitive user content,
* fail gracefully,
* allow recovery where practical.

Never allow one bad file to crash a library-wide operation.

---

# 20. Database Rules

Database operations must be designed for scale.

Use:

* appropriate indexes,
* transactions where required,
* batch inserts/updates,
* pagination,
* migrations.

Do not perform unnecessary database writes.

Do not store enormous duplicated blobs when a reference or normalized representation is sufficient.

Never store derived data without understanding how it will be invalidated.

---

# 21. File Handling

Never modify the user's original files unless the user explicitly requests an action that modifies them.

The index should reference original content.

If VoraFind creates thumbnails, extracted text, embeddings, or other derived data, clearly distinguish derived data from original files.

---

# 22. Background Work

Background processing must be:

* battery-conscious,
* resumable,
* cancellable,
* failure-tolerant.

Do not assume Android will allow unrestricted background execution.

Design around Android's actual background execution model.

---

# 23. Testing

Every meaningful feature must have appropriate tests.

Prefer:

### Unit tests

For:

* search logic,
* ranking,
* query parsing,
* indexing state,
* database logic,
* transformations.

### Widget tests

For:

* search UI,
* result states,
* loading states,
* error states.

### Integration tests

Where necessary for:

* Android platform integration,
* MediaStore,
* permissions,
* file discovery,
* end-to-end indexing/search.

Do not write tests solely to increase coverage numbers.

Tests must verify actual behavior.

---

# 24. Analyzer / Formatting

Before completing a task:

```bash
dart format .
flutter analyze
flutter test
```

If the project supports a relevant Android build verification, run it as appropriate.

Do not leave analyzer errors unresolved.

Do not ignore warnings without understanding them.

---

# 25. Git Rules

Keep commits focused.

Use clear conventional-style commit messages.

Examples:

```text
feat: add MediaStore indexing foundation
feat: implement local filename search
fix: resume interrupted indexing
perf: optimize search result ranking
refactor: simplify index processing pipeline
test: add search ranking coverage
chore: update project configuration
```

Do not mix unrelated changes into one commit.

Before committing:

1. Review `git status`.
2. Review `git diff`.
3. Check for secrets.
4. Check generated files.
5. Run relevant tests.
6. Run analyzer.
7. Confirm the implementation matches the requested task.

---

# 26. GitHub Rules

When instructed to commit and push:

1. Inspect the current branch.
2. Ensure the working tree is understood.
3. Review the diff.
4. Commit the changes.
5. Push to the intended remote/branch.
6. Report:

    * commit hash,
    * branch,
    * push result.

Never force-push unless explicitly instructed.

Never rewrite unrelated commits.

---

# 27. Do Not Overbuild

This is extremely important.

Do not implement future functionality just because it appears in `PRD.md`.

For example, if the current task is establishing the project foundation, do NOT automatically implement:

* MediaStore indexing,
* OCR,
* semantic search,
* embeddings,
* AI,
* duplicate detection,
* face recognition,
* cloud sync,
* advanced search,
* monetization.

Implement only the current requested phase.

---

# 28. Do Not Assume

Never say:

> "This probably already exists."

Inspect the repository.

Never say:

> "I'll recreate this architecture."

Inspect the existing architecture first.

Never assume:

* package versions,
* Android configuration,
* permissions,
* existing screens,
* database schema,
* navigation,
* tests,
* build configuration.

Verify them.

---

# 29. Minimize Destructive Changes

Before modifying an existing implementation:

* understand why it exists,
* determine its dependencies,
* identify affected behavior,
* make the smallest safe change.

Do not rewrite large sections of code to solve a small issue.

---

# 30. UI Quality Bar

The final interface should feel like a serious production application.

Pay attention to:

* spacing,
* typography,
* hierarchy,
* touch targets,
* empty states,
* loading states,
* error states,
* transitions,
* scrolling,
* keyboard behavior,
* dark mode,
* accessibility.

Do not use placeholder UI when implementing a production feature unless explicitly instructed.

---

# 31. Performance Quality Bar

The application must remain responsive during:

* indexing,
* database writes,
* OCR,
* search,
* thumbnail generation.

Avoid jank caused by expensive synchronous work.

Measure before making speculative optimizations.

When performance matters, prefer evidence from profiling or benchmarks over assumptions.

---

# 32. Security

Never commit:

* API keys,
* passwords,
* signing keys,
* keystores,
* private certificates,
* tokens,
* credentials,
* `.env` secrets.

If a secret is accidentally discovered in the repository, stop and report it rather than silently committing it.

---

# 33. Documentation

Document non-obvious engineering decisions.

Good documentation explains:

* why something exists,
* why a particular approach was selected,
* platform limitations,
* performance constraints,
* privacy implications.

Do not write documentation that merely restates obvious code.

---

# 34. Task Execution Protocol

For every task, follow this process.

## Step 1 — Understand

Read:

* `AGENTS.md`
* `PRD.md`
* relevant project files.

## Step 2 — Inspect

Determine:

* current architecture,
* current implementation,
* relevant dependencies,
* affected files,
* tests.

## Step 3 — Plan

Create a concise implementation plan.

Identify:

* files to change,
* files to create,
* risks,
* tests required.

## Step 4 — Implement

Implement the smallest correct solution.

Do not expand scope.

## Step 5 — Verify

Run:

```bash
dart format .
flutter analyze
flutter test
```

Run additional platform/build checks when appropriate.

## Step 6 — Review

Inspect:

```bash
git status
git diff
```

Check for:

* accidental changes,
* generated files,
* secrets,
* debug code,
* dead code,
* unnecessary dependencies.

## Step 7 — Commit

Create a focused commit when instructed.

## Step 8 — Push

Push to the configured GitHub remote when instructed.

## Step 9 — Report

Always report:

* what changed,
* files changed,
* dependencies added/removed,
* permissions added/removed,
* tests run,
* analyzer result,
* build result,
* commit hash,
* push result,
* anything that remains unresolved.

---

# 35. Scope Control

If a task exposes a problem outside the requested scope:

1. Do not silently expand the task.
2. Fix it only if it is required for the current task to function correctly.
3. Otherwise report it separately.

Example:

> "The requested feature is complete. During implementation I found an unrelated issue in X. I did not modify it."

This prevents uncontrolled project growth.

---

# 36. Definition of Done

A task is not complete merely because the code compiles.

A task is complete when:

* the requested behavior works,
* the implementation fits the architecture,
* the UI is production-quality where applicable,
* edge cases are considered,
* tests are appropriate,
* analyzer passes,
* formatting is clean,
* no unnecessary dependency was added,
* no unnecessary permission was added,
* no secrets were introduced,
* the diff is reviewed,
* the implementation remains within scope.

---

# 37. VoraFind North Star

Always remember:

> **VoraFind is a personal search engine, not merely a file manager.**

The long-term objective is to make this possible:

> "I know I saved it somewhere."

…and VoraFind finds it.

Build toward that goal without sacrificing:

**speed, accuracy, privacy, simplicity, and reliability.**
