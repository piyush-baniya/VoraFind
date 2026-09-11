import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_info.dart';
import '../../core/indexing/indexing_coordinator.dart';
import '../../core/indexing/indexing_providers.dart';
import '../../core/platform/content_access_models.dart' show ContentCategory;
import '../../core/search/search_error.dart';
import '../../core/search/search_field.dart';
import '../../core/search/search_providers.dart';
import '../../core/search/search_query.dart';
import '../../core/search/search_result.dart';
import '../../core/theme/app_colors.dart';

/// VoraFind's primary surface: a search box over the local media index.
///
/// Keeps the search field on its own `Timer` debounce so a full query is only
/// sent to the Riverpod layer once the user pauses typing.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  SearchQuery _query = const SearchQuery();

  // Background indexing is driven by app lifecycle: the full local pipeline
  // (media sync → documents → OCR) starts when the app comes to the
  // foreground and is cancelled when it hides, so extraction never keeps
  // chewing battery while the app is away (AGENTS.md §22).
  late final AppLifecycleListener _lifecycleListener = AppLifecycleListener(
    onResume: () => unawaited(ref.read(indexingCoordinatorProvider).start()),
    onPause: () => ref.read(indexingCoordinatorProvider).cancel(),
  );

  @override
  void initState() {
    super.initState();
    // AppLifecycleListener.onResume does not fire on the initial attach, so
    // the first indexing run is kicked once here; later runs are lifecycle-
    // driven. The coordinator is single-flight, so both triggers coexist.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(indexingCoordinatorProvider).start());
      }
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _submit(text);
    });
  }

  void _submit(String text) {
    final query = SearchQuery(text: text);
    setState(() => _query = query);
    ref.read(searchResultsProvider.notifier).updateQuery(query);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = const SearchQuery());
    ref.read(searchResultsProvider.notifier).updateQuery(_query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              const _SearchHeader(),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SearchField(
                  controller: _controller,
                  onChanged: _onTextChanged,
                  onSubmitted: (text) {
                    _debounce?.cancel();
                    _submit(text);
                  },
                  onClear: _clear,
                ),
              ),
              _indexingStatusLine(),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final searching = ref.watch(searchResultsProvider);

    if (!_query.hasContent) {
      return const _IdleState();
    }

    return searching.when(
      loading: () => const _LoadingState(),
      error: (error, _) => _ErrorState(
        message: error is SearchException ? error.message : 'Search failed.',
      ),
      data: (outcome) {
        if (outcome.results.isEmpty) {
          return const _NoResultsState();
        }
        return _ResultsList(results: outcome.results);
      },
    );
  }

  /// Slim indexing line under the search field. While a run is active it
  /// shows live pipeline progress (so the phone does not "do nothing" while
  /// the library is being indexed); a terminal state leaves a one-line
  /// confirmation in the idle view with a Retry/Resume action where useful.
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
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
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
                const SizedBox(width: 8),
              ] else ...[
                Icon(
                  snapshot.phase == IndexingPhase.failed
                      ? Icons.error_outline_rounded
                      : Icons.task_alt_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  _label(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (!running) _terminalAction(theme),
            ],
          ),
          ..._progressRows(),
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

  List<Widget> _progressRows() {
    final fraction = _enrichFraction();
    if (fraction == null) return const [];
    return [
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 3,
          backgroundColor: AppColors.divider,
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

/// Slim brand row: the mark plus the wordmark, kept compact so the search
/// field stays the primary interaction.
class _SearchHeader extends StatelessWidget {
  const _SearchHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.accentSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accentRing),
            ),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                Icons.search_rounded,
                color: AppColors.accent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            AppInfo.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Search your phone…',
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: AppColors.textTertiary,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textSecondary,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) {
              return const SizedBox.shrink();
            }
            return IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.textSecondary,
              ),
              tooltip: 'Clear search',
              onPressed: onClear,
            );
          },
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Idle state before the user searches. When the index is empty this becomes
/// an honest onboarding hint instead of pretending results will appear.
class _IdleState extends ConsumerWidget {
  const _IdleState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(indexStatsProvider);

    return stats.maybeWhen(
      data: (index) {
        final empty = index.total == 0;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.travel_explore_rounded,
                  size: 48,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 16),
                Text(
                  empty
                      ? 'Nothing indexed yet'
                      : 'Find anything you have saved',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  empty
                      ? 'VoraFind will search local files once the index is ready.'
                      : 'Search files, folders, and music metadata — all on this device.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

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
              Icons.search_off_rounded,
              size: 44,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text('No files matched', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Try a different name, folder, or media word.',
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
  const _ErrorState({required this.message});

  final String message;

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
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text('Search failed', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
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

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results});

  final List<SearchResult> results;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          _SearchResultTile(result: results[index]),
    );
  }
}

/// One ranked result. Includes the "why this matched" line the product
/// mandates ("Matched in name: aadhaar, card"), so relevance is explainable.
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchSummary = _matchSummary(result.matches);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CategoryGlyph(category: result.category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (result.relativePath != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      result.relativePath!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _metaLine(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (matchSummary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      matchSummary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _metaLine() {
    final parts = <String>[_categoryLabel(result.category)];
    final size = result.sizeBytes;
    if (size != null) parts.add(_formatBytes(size));
    final date = result.dateModified;
    if (date != null) parts.add(_formatDate(date));
    final duration = result.durationMs;
    if (duration != null && duration > 0) parts.add(_formatDuration(duration));
    return parts.join(' · ');
  }

  /// Composes the explainable match line from ranker diagnostics:
  /// `Matched in name: aadhaar, card` (distinct tokens per field, joined).
  static String _matchSummary(List<MatchInfo> matches) {
    if (matches.isEmpty) return '';
    final byField = <SearchField, List<String>>{};
    for (final match in matches) {
      byField.putIfAbsent(match.field, () => []).add(match.token);
    }
    final segments = byField.entries.map((entry) {
      final tokens = entry.value.toSet().toList()..sort();
      return '${_fieldLabel(entry.key)}: ${tokens.join(', ')}';
    });
    return 'Matched in ${segments.join(' · ')}';
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
    SearchField.semantic => 'semantic match',
  };

  static String _categoryLabel(ContentCategory category) => switch (category) {
    ContentCategory.images => 'Image',
    ContentCategory.videos => 'Video',
    ContentCategory.audio => 'Audio',
    ContentCategory.documents => 'Document',
  };

  static String _formatBytes(int bytes) {
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

  static String _formatDate(int epochSeconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatDuration(int milliseconds) {
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

class _CategoryGlyph extends StatelessWidget {
  const _CategoryGlyph({required this.category});

  final ContentCategory category;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (category) {
      ContentCategory.images => (Icons.image_outlined, AppColors.accent),
      ContentCategory.videos => (Icons.videocam_outlined, AppColors.accent),
      ContentCategory.audio => (Icons.music_note_rounded, AppColors.accent),
      ContentCategory.documents => (
        Icons.description_outlined,
        AppColors.accent,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.accentSubtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}
