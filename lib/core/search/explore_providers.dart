import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/content_access_models.dart' show ContentCategory;
import 'search_providers.dart';
import 'search_query.dart';
import 'search_result.dart';

/// The curated browse views on the Explore tab. Each filter is a deterministic
/// [SearchQuery] over the durable index so Explore shares the exact same ranked
/// retrieval pipeline as the search box (no second retrieval path, docs
/// `search.md`).
enum ExploreFilter {
  recent,
  images,
  videos,
  screenshots,
  documents,
  pdfs,
  audio,
  largeFiles;

  String get label => switch (this) {
    recent => 'Recent',
    images => 'Images',
    videos => 'Videos',
    screenshots => 'Screenshots',
    documents => 'Documents',
    pdfs => 'PDFs',
    audio => 'Audio',
    largeFiles => 'Large files',
  };

  /// Chip glyph, tinted with the theme accent by the UI.
  IconData get icon => switch (this) {
    recent => Icons.history_rounded,
    images => Icons.image_outlined,
    videos => Icons.videocam_outlined,
    screenshots => Icons.collections_outlined,
    documents => Icons.description_outlined,
    pdfs => Icons.picture_as_pdf_outlined,
    audio => Icons.music_note_rounded,
    largeFiles => Icons.perm_media_outlined,
  };

  /// Deterministic query for this filter. Categories filter over MediaStore
  /// media; documents are indexed separately (SAF). `isScreenshot` and
  /// `minSizeBytes` map straight onto `media_items` columns.
  SearchQuery get query => switch (this) {
    recent => const SearchQuery(categories: ContentCategory.values, limit: 50),
    images => const SearchQuery(
      categories: [ContentCategory.images],
      limit: 50,
    ),
    videos => const SearchQuery(
      categories: [ContentCategory.videos],
      limit: 50,
    ),
    screenshots => const SearchQuery(isScreenshot: true, limit: 50),
    documents => const SearchQuery(
      categories: [ContentCategory.documents],
      limit: 50,
    ),
    pdfs => const SearchQuery(
      documentTypes: {SearchDocumentType.pdf},
      limit: 50,
    ),
    audio => const SearchQuery(categories: [ContentCategory.audio], limit: 50),
    largeFiles => const SearchQuery(minSizeBytes: 50 * 1024 * 1024, limit: 50),
  };
}

/// Ranked outcome for one Explore filter. Runs through [searchServiceProvider]
/// (the same bounded pipeline as typing), so results stay deterministic and
/// never scan the whole library.
final exploreResultsProvider =
    FutureProvider.family<SearchOutcome, ExploreFilter>(
      (ref, filter) async => SearchOutcome(
        results: await ref.watch(searchServiceProvider).search(filter.query),
      ),
    );

/// Recency-ordered slice for the Home discovery grid. `categories: values`
/// makes the query non-empty so it actually traverses the index (an all-types,
/// no-keyword query would otherwise be considered idle).
final recentItemsProvider = FutureProvider<SearchOutcome>((ref) async {
  return SearchOutcome(
    results: await ref.watch(searchServiceProvider).search(
      const SearchQuery(categories: ContentCategory.values, limit: 12),
    ),
  );
});
