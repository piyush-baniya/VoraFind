import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search/search_providers.dart';
import '../../core/search/similar_image_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/visual/image_pixel_source.dart'
    show ImagePixelPng, ImagePixelSource;
import '../../core/visual/image_visual_providers.dart'
    show imagePixelSourceProvider;

/// On-device "find images like this one" (docs `similar-image-search.md`).
///
/// Two entry points, one screen:
///
/// * Flow A — the reference is an indexed image (its stored embedding is
///   reused; opened from a search result's "Similar" action);
/// * Flow B — the reference is an external picked image (decoded and embedded
///   ephemerally; opened from the home screen's "Find similar image" action).
///
/// The reference preview and every result thumbnail are PNG bytes decoded on
/// the platform — no original file bytes are ever stored by VoraFind.
class SimilarImagesScreen extends ConsumerStatefulWidget {
  const SimilarImagesScreen({super.key, required this.reference});

  final SimilarImageReference reference;

  @override
  ConsumerState<SimilarImagesScreen> createState() =>
      _SimilarImagesScreenState();
}

class _SimilarImagesScreenState extends ConsumerState<SimilarImagesScreen> {
  AsyncValue<SimilarImageOutcome> _outcome =
      const AsyncValue<SimilarImageOutcome>.loading();

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _outcome = const AsyncValue<SimilarImageOutcome>.loading();
    });
    try {
      final service = ref.read(similarImageServiceProvider);
      final outcome = await service.findSimilar(reference: widget.reference);
      if (!mounted) return;
      setState(() => _outcome = AsyncValue.data(outcome));
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _outcome = AsyncValue.error(error, stackTrace));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Similar images'),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.background,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReferenceHeader(reference: widget.reference),
            const SizedBox(height: 12),
            Expanded(
              child: _outcome.when(
                loading: () => const _SearchingState(),
                error: (error, _) =>
                    _ErrorState(message: _errorMessage(error), onRetry: _run),
                data: (outcome) => outcome.isEmpty
                    ? const _EmptyState()
                    : _ResultsGrid(results: outcome.results),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// User-facing explanation of why the search could not produce results —
  /// never a stack trace or user content (AGENTS.md §19).
  static String _errorMessage(Object error) {
    if (error is SimilarImageException) {
      return switch (error.error) {
        SimilarImageErrorCode.notIndexed =>
          "This image isn't fingerprinted yet. How Similar works: VoraFind "
              'stores a local feature of every indexed photo, and finds '
              'others nearby. Run indexing once and try again.',
        SimilarImageErrorCode.decodeFailed =>
          "Couldn't read that image for comparison.",
        SimilarImageErrorCode.unavailable =>
          "The local image model isn't available on this device.",
        SimilarImageErrorCode.failed => 'Something went wrong while searching.',
      };
    }
    return 'Something went wrong while searching.';
  }
}

/// Anchored reference summary: the preview thumbnail plus the reference name,
/// so the user always knows what is being compared against.
class _ReferenceHeader extends StatelessWidget {
  const _ReferenceHeader({required this.reference});

  final SimilarImageReference reference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          _PreviewThumb(contentUri: reference.contentUri, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reference.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Reference image',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchingState extends StatelessWidget {
  const _SearchingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 14),
          Text(
            'Finding similar images…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 44,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text('No similar images found', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Every indexed photo gets a local fingerprint. As more of your '
              'photos are analyzed, similar-image results improve.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_search_rounded,
              size: 44,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not compare images',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// Ranked thumbnail grid. Each tile shows the PNG preview, the file name, and
/// the similarity (as a percentage) — the "how close is this" context for the
/// row without burying the user in numbers.
class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({required this.results});

  final List<SimilarImageResult> results;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) =>
          _SimilarImageTile(result: results[index]),
    );
  }
}

class _SimilarImageTile extends StatelessWidget {
  const _SimilarImageTile({required this.result});

  final SimilarImageResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.expand(
              child: _PreviewThumb(contentUri: result.contentUri, size: 512),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          result.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${(result.similarity * 100).clamp(0, 100).toStringAsFixed(0)}% similar',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

/// Lazily loads the bounded PNG preview for a content URI, falling back to a
/// quiet placeholder (or a broken-image glyph on decode errors). No original
/// bytes are ever kept in memory or on disk (privacy §8).
class _PreviewThumb extends ConsumerStatefulWidget {
  const _PreviewThumb({required this.contentUri, required this.size});

  final String contentUri;
  final double size;

  @override
  ConsumerState<_PreviewThumb> createState() => _PreviewThumbState();
}

class _PreviewThumbState extends ConsumerState<_PreviewThumb> {
  late Future<ImagePixelPng> _future;

  ImagePixelSource get _pixelSource => ref.read(imagePixelSourceProvider);

  @override
  void initState() {
    super.initState();
    _future = _pixelSource.readImagePng(contentUri: widget.contentUri);
  }

  @override
  void didUpdateWidget(covariant _PreviewThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentUri != widget.contentUri) {
      _future = _pixelSource.readImagePng(contentUri: widget.contentUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.expand(
          child: FutureBuilder<ImagePixelPng>(
            future: _future,
            builder: (context, snapshot) {
              final png = snapshot.data;
              if (png != null &&
                  png.errorCode == null &&
                  png.bytes.isNotEmpty) {
                return Image.memory(
                  png.bytes,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              }
              if (png != null && png.errorCode != null) {
                return const _ThumbPlaceholder(
                  icon: Icons.broken_image_outlined,
                );
              }
              return const _ThumbPlaceholder(icon: Icons.image_outlined);
            },
          ),
        ),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(child: Icon(icon, color: AppColors.textTertiary, size: 22));
  }
}
