import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/media_repository.dart';
import '../database/providers.dart';
import 'search_query.dart';
import 'search_result.dart';
import 'search_service.dart';

/// Creates a search over the durable media index.
final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(repository: ref.watch(mediaRepositoryProvider));
});

/// Typed confirmation that a search completed (or an empty outcome for an
/// idle/empty query). Backed by a [Notifier] instead of a plain FutureProvider
/// so rapid typed queries can be superseded cleanly.
final searchResultsProvider =
    NotifierProvider<SearchResultsNotifier, AsyncValue<SearchOutcome>>(
      SearchResultsNotifier.new,
    );

/// Runs searches one at a time and discards stale completions.
///
/// `updateQuery` can be called as fast as the user types (the screen debounces
/// before calling it, but the notifier must still be safe under races): every
/// call bumps [_generation], and a finished search only publishes if its
/// generation is still current.
class SearchResultsNotifier extends Notifier<AsyncValue<SearchOutcome>> {
  int _generation = 0;

  @override
  AsyncValue<SearchOutcome> build() {
    return const AsyncValue.data(SearchOutcome.empty());
  }

  /// Runs [query] if it has any content; otherwise restores the idle outcome
  /// without touching the index.
  void updateQuery(SearchQuery query) {
    final generation = ++_generation;
    if (!query.hasContent) {
      state = const AsyncValue.data(SearchOutcome.empty());
      return;
    }
    state = const AsyncLoading<SearchOutcome>();
    _run(ref.read(searchServiceProvider), query, generation);
  }

  Future<void> _run(
    SearchService service,
    SearchQuery query,
    int generation,
  ) async {
    try {
      final results = await service.search(query);
      _publish(generation, AsyncValue.data(SearchOutcome(results: results)));
    } catch (error, stackTrace) {
      _publish(generation, AsyncValue.error(error, stackTrace));
    }
  }

  void _publish(int generation, AsyncValue<SearchOutcome> next) {
    if (generation != _generation || !ref.mounted) return;
    state = next;
  }
}

/// Total indexed files, used by the search screen to distinguish a new user
/// (empty index) from a real "no results" state.
final indexStatsProvider = FutureProvider<MediaIndexStats>((ref) {
  return ref.watch(mediaRepositoryProvider).stats();
});
