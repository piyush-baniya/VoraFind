import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search/explore_providers.dart';
import '../../core/search/search_result.dart';
import '../../core/theme/app_tokens.dart';
import '../shared/widgets/vora_result_tile.dart';
import '../shared/widgets/vora_surfaces.dart';

/// Explore tab: curated browse views over the local index.
///
/// One horizontal chip row picks a deterministic [ExploreFilter]; results come
/// from the exact same ranked retrieval pipeline as the search box (no second
/// path). Image-heavy filters render as a square-tile grid; everything else as
/// list rows.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  ExploreFilter _selected = ExploreFilter.recent;

  /// Image-first filters use a tile grid; the rest a list.
  static bool _usesGrid(ExploreFilter filter) =>
      filter == ExploreFilter.images || filter == ExploreFilter.screenshots;

  @override
  Widget build(BuildContext context) {
    final outcome = ref.watch(exploreResultsProvider(_selected));

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VoraSpace.lg,
              VoraSpace.lg,
              VoraSpace.lg,
              VoraSpace.sm,
            ),
            child: Text(
              'Explore',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          _chipRow(),
          const SizedBox(height: VoraSpace.sm),
          Expanded(
            child: AnimatedSwitcher(
              duration: VoraDuration.slow,
              child: outcome.maybeWhen(
                data: (data) {
                  if (data.results.isEmpty) {
                    return const VoraEmptyState(
                      icon: Icons.collections_bookmark_outlined,
                      title: 'Nothing here yet',
                      caption: 'Content appears once the local index has it. Everything stays on this device.',
                    );
                  }
                  return _resultsFor(_selected, data.results);
                },
                loading: () => const VoraLoadingView(),
                orElse: () => const VoraLoadingView(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipRow() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: VoraSpace.lg),
        scrollDirection: Axis.horizontal,
        itemCount: ExploreFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: VoraSpace.sm),
        itemBuilder: (context, index) {
          final filter = ExploreFilter.values[index];
          return ChoiceChip(
            key: ValueKey('filter-${filter.name}'),
            avatar: Icon(filter.icon, size: VoraIconSize.sm),
            label: Text(filter.label),
            selected: _selected == filter,
            onSelected: (_) => setState(() => _selected = filter),
          );
        },
      ),
    );
  }

  Widget _resultsFor(ExploreFilter filter, List<SearchResult> results) {
    if (_usesGrid(filter)) {
      return GridView.builder(
        key: ValueKey('grid-${filter.name}'),
        padding: const EdgeInsets.fromLTRB(
          VoraSpace.lg,
          VoraSpace.xs,
          VoraSpace.lg,
          VoraSpace.md,
        ),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: VoraSpace.md,
          crossAxisSpacing: VoraSpace.md,
          childAspectRatio: 0.72,
        ),
        itemCount: results.length,
        itemBuilder: (context, index) => VoraGridCard(result: results[index]),
      );
    }
    return VoraResultList(
      key: ValueKey('list-${filter.name}'),
      results: results,
      topPadding: VoraSpace.xs,
    );
  }
}
