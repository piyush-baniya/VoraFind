import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/providers.dart' show databaseProvider;
import 'drift_visual_repository.dart';
import 'video_frame_sampler.dart';
import 'visual_frame_classifier.dart';
import 'visual_index_coordinator.dart';
import 'visual_repository.dart';

// The classifier behind all video visual enrichment. Prompt #15 ships the real
// on-device model: the [NeuralVisualFrameClassifier] runs the bundled int8
// MobileNetV2 through ONNX Runtime, fully offline (docs
// video-visual-search.md, Selected model). It sits behind the same
// [VisualFrameClassifier] interface the deterministic classifier implements,
// so tests and future models swap in without touching the pipeline.
//
// The classifier is created lazily (no asset loading, no native initialization
// at construction) and the model is loaded on the first classify; until then it
// reports available, and a failed load flips it terminal.
final visualFrameClassifierProvider = Provider<VisualFrameClassifier>(
  (ref) => NeuralVisualFrameClassifier(),
);

// Sampler entry point to the native Android video frame extraction
// (`vorafind/video` method channel, VideoFrameBridge.kt).
final videoFrameSamplerProvider = Provider<VideoFrameSampler>(
  (ref) => MethodChannelVideoFrameSampler(),
);

// Indexing-side data access over video_visual_status / video_visual_frames.
// Single source of truth for both enrichment and retrieval so the coordinator
// and SearchService share one repository instance.
final visualIndexRepositoryProvider = Provider<VisualIndexRepository>((ref) {
  return DriftVisualRepository(ref.watch(databaseProvider));
});

// Search-side retrieval over the completed frame store. Backed by the same
// DriftVisualRepository instance as the indexing side, but exposes only the
// read-only retrieval interface so search code cannot mutate the store.
final visualSearchRepositoryProvider = Provider<VisualSearchRepository>((ref) {
  return DriftVisualRepository(ref.watch(databaseProvider));
});

// Drives the optional video visual enrichment stage (docs
// video-visual-search.md, Indexing lifecycle). null when the classifier is
// unavailable; the indexing pipeline skips the stage entirely in that case.
final visualIndexCoordinatorProvider = Provider<VisualIndexCoordinator?>((ref) {
  final classifier = ref.watch(visualFrameClassifierProvider);
  if (!classifier.isAvailable) return null;
  final sampler = ref.watch(videoFrameSamplerProvider);
  final repository = ref.watch(visualIndexRepositoryProvider);
  return VisualIndexCoordinator(
    classifier: classifier,
    sampler: sampler,
    repository: repository,
  );
});
