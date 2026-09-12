import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/providers.dart' show databaseProvider;
import 'drift_image_visual_repository.dart';
import 'image_embedding_provider.dart';
import 'image_pixel_source.dart';
import 'image_visual_index_coordinator.dart';
import 'image_visual_repository.dart';

// The embedding provider behind all image similarity enrichment. Prompt #16
// ships the real on-device model: the [NeuralImageEmbeddingProvider] runs the
// bundled sliced MobileNetV2 feature graph through ONNX Runtime, fully offline
// (docs similar-image-search.md, Selected model). It sits behind the same
// [ImageEmbeddingProvider] interface the deterministic provider implements, so
// tests and future models swap in without touching the pipeline.
//
// The provider is created lazily (no asset loading, no native initialization
// at construction) and the model is loaded on the first embed; until then it
// reports available, and a failed load flips it terminal.
final imageEmbeddingProviderProvider = Provider<ImageEmbeddingProvider>(
  (ref) => NeuralImageEmbeddingProvider(),
);

// Pixel access entry point to the native Android image decoder and picker
// (`vorafind/image` method channel, ImageVisualBridge.kt).
final imagePixelSourceProvider = Provider<ImagePixelSource>(
  (ref) => MethodChannelImagePixelSource(),
);

// Indexing-side data access over image_visual_embeddings. Single source of
// truth for both enrichment and retrieval so the coordinator and the similar
// image search share one repository instance.
final imageVisualIndexRepositoryProvider = Provider<ImageVisualIndexRepository>(
  (ref) {
    return DriftImageVisualRepository(ref.watch(databaseProvider));
  },
);

// Search-side retrieval over the completed image vector store. Backed by the
// same DriftImageVisualRepository as the indexing side, but exposes only the
// read-only retrieval interface so search code cannot mutate the store.
final imageVisualSearchRepositoryProvider =
    Provider<ImageVisualSearchRepository>((ref) {
      return DriftImageVisualRepository(ref.watch(databaseProvider));
    });

// Drives the optional image-feature enrichment stage (docs
// similar-image-search.md, Indexing lifecycle). null when the provider is
// unavailable; the indexing pipeline skips the stage entirely in that case.
final imageVisualIndexCoordinatorProvider =
    Provider<ImageVisualIndexCoordinator?>((ref) {
      final provider = ref.watch(imageEmbeddingProviderProvider);
      if (!provider.isAvailable) return null;
      final pixelSource = ref.watch(imagePixelSourceProvider);
      final repository = ref.watch(imageVisualIndexRepositoryProvider);
      return ImageVisualIndexCoordinator(
        provider: provider,
        pixelSource: pixelSource,
        repository: repository,
      );
    });
