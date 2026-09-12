import 'package:flutter/material.dart';

import '../../../core/platform/content_access_models.dart' show ContentCategory;
import '../../../core/search/search_field.dart';
import '../../../core/search/search_result.dart';
import '../../../core/search/similar_image_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../features/similar_images/similar_images_screen.dart'
    show SimilarImagesScreen;
import 'vora_thumbnail.dart';

/// Shared formatters for content metadata across result tiles and grids.
abstract final class VoraFormatters {
  static String categoryLabel(ContentCategory category) => switch (category) {
    ContentCategory.images => 'Image',
    ContentCategory.videos => 'Video',
    ContentCategory.audio => 'Audio',
    ContentCategory.documents => 'Document',
  };

  static String bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    var unit = -1;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
  }

  static String date(int epochSeconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000)
        .toLocal();
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String duration(int milliseconds) {
    final totalSeconds = (milliseconds / 1000).round();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Category glyph shown when a result has no decodable thumbnail.
///
/// Classification-only: the same icon and tint for every row of a category —
/// never per-content colors (design system §38).
class VoraCategoryGlyph extends StatelessWidget {
  const VoraCategoryGlyph({super.key, required this.category, this.size = 40});

  final ContentCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = switch (category) {
      ContentCategory.images => Icons.image_outlined,
      ContentCategory.videos => Icons.videocam_outlined,
      ContentCategory.audio => Icons.music_note_rounded,
      ContentCategory.documents => Icons.description_outlined,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.vora.accentSubtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, color: context.vora.accent, size: size * 0.55),
      ),
    );
  }
}

/// One ranked search result.
///
/// Shows a small thumbnail for images (decoded locally at a bounded size) or
/// the category glyph otherwise, one metadata line (type · date · size), and
/// — the product-mandated explainability — terse match pills explaining *why*
/// the row matched. Image results get the similar-image action (Flow A).
class VoraResultTile extends StatelessWidget {
  const VoraResultTile({super.key, required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.vora.surface,
        borderRadius: BorderRadius.circular(VoraRadius.lg),
        border: Border.all(color: context.vora.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VoraSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _leading(context),
            const SizedBox(width: VoraSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (result.relativePath != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      result.relativePath!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.vora.textTertiary),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _metaLine(),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.vora.textSecondary),
                  ),
                  if (result.matches.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    MatchPillRow(matches: result.matches),
                  ],
                ],
              ),
            ),
            if (result.category == ContentCategory.images) ...[
              const SizedBox(width: VoraSpace.xs),
              _SimilarActionIcon(result: result),
            ],
          ],
        ),
      ),
    );
  }

  Widget _leading(BuildContext context) {
    if (result.category == ContentCategory.images) {
      return Semantics(
        label: '${result.displayName} thumbnail',
        child: VoraThumbnail(
          contentUri: result.contentUri,
          size: 60,
          fallback: VoraCategoryGlyph(category: result.category, size: 60),
        ),
      );
    }
    return VoraCategoryGlyph(category: result.category, size: 60);
  }

  String _metaLine() {
    final parts = <String>[VoraFormatters.categoryLabel(result.category)];
    final size = result.sizeBytes;
    if (size != null) parts.add(VoraFormatters.bytes(size));
    final date = result.dateModified;
    if (date != null) parts.add(VoraFormatters.date(date));
    final duration = result.durationMs;
    if (duration != null && duration > 0) {
      parts.add(VoraFormatters.duration(duration));
    }
    return parts.join(' · ');
  }
}

/// Lazy vertical list of [VoraResultTile]s — the shared ranked-results layout
/// for search results and list-styled Explore filters.
class VoraResultList extends StatelessWidget {
  const VoraResultList({super.key, required this.results, this.topPadding = 0});

  final List<SearchResult> results;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        VoraSpace.lg,
        topPadding,
        VoraSpace.lg,
        VoraSpace.md,
      ),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: VoraSpace.sm),
      itemBuilder: (context, index) => VoraResultTile(result: results[index]),
    );
  }
}

/// Square thumbnail card for image-heavy grids (Explore). Keeps the tile
/// compact: thumbnail + one-line name + one-line meta.
class VoraGridCard extends StatelessWidget {
  const VoraGridCard({super.key, required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${result.displayName}, ${VoraFormatters.categoryLabel(result.category)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(VoraRadius.lg),
            child: AspectRatio(
              aspectRatio: 1,
              child: VoraThumbnail(
                contentUri: result.contentUri,
                size: double.infinity,
                fallback: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.vora.surfaceElevated,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: context.vora.textTertiary,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            result.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (result.sizeBytes != null)
            Text(
              VoraFormatters.bytes(result.sizeBytes!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.vora.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// The "why this matched" pills. One pill per distinct signal: the field label
/// plus the actual matched tokens, so relevance is concrete rather than an
/// unexplained score (`docs/search.md` §28, design system §30). Examples:
///
/// ```text
/// name: invoice      OCR text: RTX 5050      conceptual similarity
/// ```
class MatchPillRow extends StatelessWidget {
  const MatchPillRow({super.key, required this.matches});

  final List<MatchInfo> matches;

  @override
  Widget build(BuildContext context) {
    final byField = <SearchField, List<String>>{};
    for (final match in matches) {
      byField.putIfAbsent(match.field, () => []).add(match.token);
    }

    final pills = byField.entries
        .map((entry) {
          return _MatchPillWidget(text: _pillText(entry.key, entry.value));
        })
        .toList(growable: false);

    if (pills.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: VoraSpace.xs,
      runSpacing: VoraSpace.xs,
      children: pills,
    );
  }

  /// `name: invoice`, `OCR text: RTX 5050`, or just the label when the field
  /// matched without a literal token (semantic/visual/blank).
  static String _pillText(SearchField field, List<String> tokens) {
    final label = _fieldLabel(field);
    final clean = tokens.where((t) => t.trim().isNotEmpty).toSet().toList()
      ..sort();
    if (clean.isEmpty) return label;
    return '$label: ${clean.take(2).join(', ')}';
  }

  static String _fieldLabel(SearchField field) => switch (field) {
    SearchField.displayName => 'name',
    SearchField.title => 'title',
    SearchField.relativePath => 'folder',
    SearchField.bucketDisplayName => 'album',
    SearchField.artist || SearchField.albumArtist => 'artist',
    SearchField.album => 'album',
    SearchField.genre => 'genre',
    SearchField.ocrText => 'OCR text',
    SearchField.documentText => 'document text',
    SearchField.semantic => 'conceptual similarity',
    SearchField.visual => 'visual content',
  };
}

class _MatchPillWidget extends StatelessWidget {
  const _MatchPillWidget({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VoraSpace.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.vora.accentSubtle,
        borderRadius: BorderRadius.circular(VoraRadius.full),
        border: Border.all(color: context.vora.accentRing),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.vora.accent, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Similar-image entry point on image results (Flow A): reuses the stored
/// image feature, no pixel decoding, result excluded from its own list.
class _SimilarActionIcon extends StatelessWidget {
  const _SimilarActionIcon({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.image_search_outlined, size: 22),
      color: context.vora.textSecondary,
      tooltip: 'Find similar image',
      visualDensity: VisualDensity.compact,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SimilarImagesScreen(
              reference: SimilarImageReference(
                stableKey: result.stableKey,
                contentUri: result.contentUri,
                displayName: result.displayName,
                relativePath: result.relativePath,
                dateModified: result.dateModified,
                imageWidth: result.width,
                imageHeight: result.height,
              ),
            ),
          ),
        );
      },
    );
  }
}
