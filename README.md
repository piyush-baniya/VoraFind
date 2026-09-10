# VoraFind

**Find anything you've saved on your phone.**

VoraFind is a privacy-first personal search engine for your device. It is designed to help you find photos, screenshots, documents, and other saved content without needing to remember filenames or folders.

## Vision

Instead of asking:

> "Where did I save that?"

VoraFind should let you ask:

> "Find the screenshot of the laptop I was researching."

and quickly find the relevant content.

## Core Principles

* 🔒 **Privacy-first** — personal content stays on the device by default.
* ⚡ **Fast** — search should feel immediate after indexing.
* 📴 **Offline-first** — core search works without an internet connection.
* 🎯 **Accurate** — results should prioritize relevance over flashy features.
* 🧠 **Intelligent** — search can eventually understand content, not just filenames.
* ✨ **Simple** — one clear search experience instead of a complicated file manager UI.

## Planned Capabilities

VoraFind is being developed incrementally.

### Core

* Device content indexing
* File metadata indexing
* Image and screenshot indexing
* OCR text search
* PDF/document text search
* Filename and keyword search
* Search filters
* Relevance-based result ranking
* Incremental and resumable indexing

### Future

* Semantic search
* Local AI
* Ask VoraFind
* Related content
* Smart collections
* Duplicate detection
* Visual search
* Optional local people/photo organization
* Share Sheet integration

See [`PRD.md`](PRD.md) for the complete product requirements.

## Privacy

VoraFind is designed around local-first processing.

The goal is for users' personal files and extracted information to remain on their device rather than being uploaded to a cloud service for normal search functionality.

Permissions will be requested only when required by the current functionality.

## Technology

VoraFind is being built with:

* **Flutter / Dart**
* **Android / Kotlin** for platform-specific functionality where appropriate
* **Riverpod** for application state where needed
* **Drift / SQLite** for local structured data where appropriate
* Local indexing and search technologies
* Local OCR and AI technologies as the product evolves

The exact technology choices may change as implementation and performance requirements become clearer.

## Project Structure

```text
VoraFind/
├── AGENTS.md       # Coding-agent instructions
├── PRD.md          # Product requirements
├── README.md       # Project overview
├── android/        # Android platform code
├── ios/            # iOS platform code
├── lib/            # Flutter application
├── test/           # Tests
└── pubspec.yaml    # Flutter dependencies/configuration
```

## Development

Make sure Flutter is installed and configured correctly.

Check the environment:

```bash
flutter doctor
```

Get dependencies:

```bash
flutter pub get
```

Format the project:

```bash
dart format .
```

Run static analysis:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

Run the application:

```bash
flutter run
```

## Development Rules

Before making changes, read:

* [`AGENTS.md`](AGENTS.md)
* [`PRD.md`](PRD.md)

Do not assume planned functionality is already implemented.

Inspect the existing repository before changing it.

Keep dependencies minimal and prioritize performance, privacy, reliability, and search accuracy.

## Status

🚧 **Early development**

The project is currently establishing its production foundation before implementing the core device-indexing and search engine.

## License

License information will be added before the first public release.
