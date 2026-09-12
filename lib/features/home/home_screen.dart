import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_info.dart';
import '../../core/database/media_repository.dart' show MediaIndexStats;
import '../../core/documents/document_providers.dart'
    show contentAccessProvider;
import '../../core/indexing/indexing_coordinator.dart';
import '../../core/indexing/indexing_providers.dart';
import '../../core/platform/content_access_models.dart' show ContentCategory;
import '../../core/search/explore_providers.dart';
import '../../core/search/search_error.dart';
import '../../core/search/search_providers.dart';
import '../../core/search/search_query.dart';
import '../../core/search/search_result.dart';
import '../../core/search/similar_image_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/visual/image_visual_providers.dart'
    show imagePixelSourceProvider;
import '../similar_images/similar_images_screen.dart';
import '../shared/widgets/vora_result_tile.dart';
import '../shared/widgets/vora_search_bar.dart';
import '../shared/widgets/vora_surfaces.dart';

/// VoraFind's primary surface (Search tab): the bottom-docked search bar over
/// local content.
///
/// Debounces typing (200 ms — fast enough for instant feel, slow enough to not
/// re-run SQLite on every key), pushes [SearchQuery] into the Riverpod search
/// layer, and renders ranked results inline. With no active query it shows
/// discovery content (recency-ordered "Recent") or the honest first-run card
/// when nothing is indexed yet.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  SearchQuery _query = const SearchQuery();
  Set<ContentCategory> _categories = const {};

  static const _debounceDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      _submit(text);
    });
  }

  void _submit(String text) {
    final query = SearchQuery(text: text, categories: _effectiveCategories);
    setState(() => _query = query);
    ref.read(searchResultsProvider.notifier).updateQuery(query);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _categories = const {};
      _query = const SearchQuery();
    });
    ref.read(searchResultsProvider.notifier).updateQuery(_query);
  }

  List<ContentCategory>? get _effectiveCategories =>
      _categories.isEmpty ? null : _categories.toList(growable: false);

  Future<void> _openFilterSheet() async {
    final selection = await showVoraFilterSheet(context, initial: _categories);
    if (selection == null || !mounted) return;
    setState(() => _categories = {...selection});
    _submit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _HomeHeader(),
            Expanded(child: _buildBody()),
            _indexingStatusLine(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VoraSpace.lg,
                VoraSpace.xs,
                VoraSpace.lg,
                VoraSpace.md,
              ),
              child: Column(
                children: [
                  if (_categories.isNotEmpty)
                    _ActiveFilterChip(
                      label: _categories.first.name,
                      onClear: _clear,
                    ),
                  const SizedBox(height: VoraSpace.sm),
                  VoraSearchBar(
                    controller: _controller,
                    hintText: 'Search your device',
                    onChanged: _onTextChanged,
                    onSubmitted: (text) {
                      _debounce?.cancel();
                      _submit(text);
                    },
                    onClear: _clear,
                    onTapFilter: _openFilterSheet,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final searching = ref.watch(searchResultsProvider);

    if (!_query.hasContent) {
      return _DiscoveryView(
        statsAsync: ref.watch(indexStatsProvider),
        recentAsync: ref.watch(recentItemsProvider),
      );
    }

    return searching.when(
      loading: () => const VoraLoadingView(),
      error: (error, _) => VoraEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Search failed',
        caption: error is SearchException ? error.message : 'Search failed.',
      ),
      data: (outcome) {
        if (outcome.results.isEmpty) {
          return const VoraEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No files matched',
            caption: 'Try a different name, folder, or media word.',
          );
        }
        return VoraResultList(
          results: outcome.results,
          topPadding: VoraSpace.sm,
        );
      },
    );
  }

  /// Slim indexing line above the search bar. While a run is active it shows
  /// live pipeline progress; a terminal state leaves a one-line confirmation
  /// with a Retry/Resume action where useful.
  Widget _indexingStatusLine() {
    final status = ref.watch(indexingStatusProvider);
    return status.maybeWhen(
      data: (snapshot) {
        final show =
            snapshot.isRunning ||
            (!_query.hasContent && snapshot.phase != IndexingPhase.idle);
        if (!show) return const SizedBox.shrink();
        return _IndexingStatusTile(
          snapshot: snapshot,
          onAction: () =>
              unawaited(ref.read(indexingCoordinatorProvider).start()),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Compact brand row: the mark plus the wordmark, kept slim so the search
/// field stays the primary interaction.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, VoraSpace.lg, 0, VoraSpace.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.vora.accentSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.vora.accentRing),
              ),
              child: SizedBox.square(
                dimension: 34,
                child: Icon(
                  Icons.search_rounded,
                  color: context.vora.accent,
                  size: VoraIconSize.md,
                ),
              ),
            ),
            const SizedBox(width: VoraSpace.md),
            Text(
              AppInfo.name,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip showing the active type filter with a one-tap clear.
class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: const Icon(Icons.tune_rounded, size: VoraIconSize.sm),
        label: Text(label),
        deleteIcon: const Icon(Icons.close_rounded, size: VoraIconSize.sm),
        onDeleted: onClear,
      ),
    );
  }
}

/// Idle state: honest onboarding when the index is empty, otherwise the
/// recency-ordered "Recent" discovery list.
class _DiscoveryView extends ConsumerWidget {
  const _DiscoveryView({required this.statsAsync, required this.recentAsync});

  final AsyncValue<MediaIndexStats> statsAsync;
  final AsyncValue<SearchOutcome> recentAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statsAsync.maybeWhen(
      data: (stats) {
        if (stats.total == 0) {
          return _FirstRunState(onGiveAccess: () => _giveAccess(context, ref));
        }
        return _RecentList(recentAsync: recentAsync);
      },
      orElse: () => const VoraLoadingView(),
    );
  }

  /// Requests media access (images) directly, then starts the pipeline — the
  /// synchronization coordinator also requests access per volume, so this is
  /// only the explicit first-run grant of the platform permission dialog.
  static Future<void> _giveAccess(BuildContext context, WidgetRef ref) async {
    final access = ref.read(contentAccessProvider);
    try {
      await access.requestMediaAccess(ContentCategory.images);
    } on Exception {
      // Permission failure isn't fatal; the coordinator surfaces the state in
      // the indexing status line and retries on the next lifecycle run.
    }
    await ref.read(indexingCoordinatorProvider).start();
  }
}

/// Pre-populated async widgets for the first-run flow are wired where the
/// provider graph lives; see [_FirstRunState].
class _FirstRunState extends StatelessWidget {
  const _FirstRunState({required this.onGiveAccess});

  final VoidCallback onGiveAccess;

  @override
  Widget build(BuildContext context) {
    return VoraEmptyState(
      icon: Icons.travel_explore_rounded,
      title: 'Nothing indexed yet',
      caption: 'Give VoraFind access and it will search files, photos, and documents saved on this device — everything stays here.',
      action: FilledButton.icon(
        onPressed: onGiveAccess,
        icon: const Icon(Icons.folder_open_rounded, size: VoraIconSize.md),
        label: const Text('Give access'),
      ),
    );
  }
}

class _RecentList extends ConsumerWidget {
  const _RecentList({required this.recentAsync});

  final AsyncValue<SearchOutcome> recentAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VoraSpace.lg),
          child: VoraSectionHeader(
            title: 'Recent',
            trailing: IconButton(
              icon: const Icon(Icons.image_search_outlined),
              color: context.vora.textSecondary,
              tooltip: 'Find similar image',
              onPressed: () => _pickSimilarImage(context, ref),
            ),
          ),
        ),
        Expanded(
          child: recentAsync.maybeWhen(
            data: (outcome) {
              if (outcome.results.isEmpty) {
                return const VoraEmptyState(
                  icon: Icons.hourglass_empty_rounded,
                  title: 'Indexing your files…',
                  caption:
                      'Your content appears here as the local index is built.',
                );
              }
              return VoraResultList(results: outcome.results);
            },
            loading: () => const VoraLoadingView(),
            orElse: () => const VoraLoadingView(),
          ),
        ),
      ],
    );
  }

  /// Flow B of similar-image search: pick any local image (system picker, no
  /// storage permission), then compare it against the index using a fresh
  /// on-device embedding that is never persisted.
  static Future<void> _pickSimilarImage(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final pixelSource = ref.read(imagePixelSourceProvider);
    final pick = await pixelSource.pickImage();
    if (pick.contentUri == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimilarImagesScreen(
          reference: SimilarImageReference(
            contentUri: pick.contentUri!,
            displayName: 'Selected image',
          ),
        ),
      ),
    );
  }
}

/// One-line indexing status with a spare progress bar while the pipeline is
/// working, plus a Retry/Resume action for terminal states that justify one.
class _IndexingStatusTile extends StatelessWidget {
  const _IndexingStatusTile({required this.snapshot, required this.onAction});

  final IndexingStatus snapshot;

  /// Starts a fresh pipeline run — used by Retry (failed) and Resume
  /// (cancelled). Single-flight, so tapping it while running is harmless.
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = snapshot.isRunning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VoraSpace.xl,
        VoraSpace.sm,
        VoraSpace.xl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (running) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: VoraSpace.sm),
              ] else ...[
                Icon(
                  snapshot.phase == IndexingPhase.failed
                      ? Icons.error_outline_rounded
                      : Icons.task_alt_rounded,
                  size: 14,
                  color: context.vora.textTertiary,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  _label(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.vora.textSecondary,
                  ),
                ),
              ),
              if (!running) _terminalAction(theme),
            ],
          ),
          ..._progressRows(context),
        ],
      ),
    );
  }

  Widget _terminalAction(ThemeData theme) {
    final label = switch (snapshot.phase) {
      IndexingPhase.cancelled => 'Resume',
      IndexingPhase.failed => 'Retry',
      _ => null,
    };
    if (label == null) return const SizedBox.shrink();
    return TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: onAction,
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  String _label() => switch (snapshot.phase) {
    IndexingPhase.preparing => 'Indexing your files…',
    IndexingPhase.discovering => 'Indexing your files…',
    IndexingPhase.persisting => _persistingLabel(),
    IndexingPhase.enriching => _enrichingLabel(),
    IndexingPhase.completed => 'Everything is indexed',
    IndexingPhase.cancelled => 'Indexing paused',
    IndexingPhase.failed => snapshot.message ?? 'Indexing couldn\'t finish',
    IndexingPhase.idle => 'Indexing your files…',
  };

  String _persistingLabel() {
    final total = snapshot.mediaIndexed;
    final changed = snapshot.mediaChanged;
    if (total == null) return 'Saving index…';
    if (changed == null || changed == 0) return '$total files indexed';
    return '$changed files updated · $total indexed';
  }

  String _enrichingLabel() {
    final doc = snapshot.documentsProcessed;
    final docTotal = snapshot.documentsTotal;
    final content = snapshot.contentProcessed;
    final contentTotal = snapshot.contentTotal;
    if (doc == null && content == null) return 'Analyzing content…';
    final docPart = doc == null || docTotal == null || docTotal == 0
        ? null
        : 'documents $doc/$docTotal';
    final contentPart =
        content == null || contentTotal == null || contentTotal == 0
        ? null
        : 'screenshots $content/$contentTotal';
    final parts = [?contentPart, ?docPart];
    if (parts.isEmpty) return 'Analyzing content…';
    return 'Analyzing · ${parts.join(' · ')}';
  }

  List<Widget> _progressRows(BuildContext context) {
    final fraction = _enrichFraction();
    if (fraction == null) return const [];
    return [
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 3,
          backgroundColor: context.vora.divider,
        ),
      ),
    ];
  }

  /// Live enrichment share for the progress bar, preferring the OCR window
  /// and falling back to documents. Null → indeterminate (no fake progress).
  double? _enrichFraction() {
    if (snapshot.phase != IndexingPhase.enriching) return null;
    final processed = snapshot.contentProcessed;
    final total = snapshot.contentTotal;
    if (processed != null && total != null && total > 0) {
      return (processed / total).clamp(0.0, 1.0);
    }
    final docProcessed = snapshot.documentsProcessed;
    final docTotal = snapshot.documentsTotal;
    if (docProcessed != null && docTotal != null && docTotal > 0) {
      return (docProcessed / docTotal).clamp(0.0, 1.0);
    }
    return null;
  }
}
