import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/providers.dart' show databaseProvider;
import 'drift_semantic_repository.dart';
import 'embedding_provider.dart';
import 'semantic_index_coordinator.dart';
import 'semantic_repository.dart';

// The local embedding model/configuration. A real LiteRT/ONNX provider
// replaces the unavailable placeholder behind the same interface (docs
// semantic-search.md, Selected model). Marked Provider (not StateNotifier) so
// swapping the implementation at app start is a single site change.
final embeddingProvider = Provider<EmbeddingProvider>(
  (ref) => const UnavailableEmbeddingProvider(),
);

// Indexing-side data access over semantic_embeddings. Single source of truth
// for both enrichment and retrieval so the coordinator and SearchService
// share one repository instance (no duplicate pools, no diverged state).
final semanticIndexRepositoryProvider = Provider<SemanticIndexRepository>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return DriftSemanticRepository(db);
});

// Search-side retrieval over the completed vector store. Backed by the same
// DriftSemanticRepository instance as the indexing side, but exposes only
// the read-only retrieval interface so search code cannot mutate the store.
final semanticSearchRepositoryProvider = Provider<SemanticSearchRepository>(
  (ref) => DriftSemanticRepository(ref.watch(databaseProvider)),
);

// Drives the optional semantic enrichment stage (docs semantic-search.md,
// Indexing lifecycle). null when no embedding model is available; the
// indexing pipeline skips the stage entirely in that case.
final semanticIndexCoordinatorProvider = Provider<SemanticIndexCoordinator?>((
  ref,
) {
  final provider = ref.watch(embeddingProvider);
  if (!provider.isAvailable) return null;
  final repository = ref.watch(semanticIndexRepositoryProvider);
  return SemanticIndexCoordinator(provider: provider, repository: repository);
});
