import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/providers.dart';
import '../database/synchronization_coordinator.dart';
import '../documents/document_providers.dart';
import '../ocr/ocr_providers.dart';
import '../platform/content_access.dart';
import '../platform/content_access_models.dart' show ContentCategory;
import '../platform/media_discovery.dart';
import '../semantic/semantic_providers.dart';
import '../visual/visual_providers.dart';
import 'indexing_coordinator.dart';

/// Adapts the media [SynchronizationCoordinator] to the pipeline's
/// [IndexingMediaSync] stage interface.
class _SynchronizationStage implements IndexingMediaSync {
  _SynchronizationStage(this._inner);

  final SynchronizationCoordinator _inner;

  @override
  Future<SyncSessionResult> run(List<ContentCategory> categories) =>
      _inner.run(categories);

  @override
  Future<void> cancel() => _inner.cancel();
}

/// The media synchronization stage (DiscoveryBridge → bounded batches →
/// batched persistence → deletion reconciliation).
final synchronizationCoordinatorProvider = Provider<SynchronizationCoordinator>(
  (ref) {
    return SynchronizationCoordinator(
      repository: ref.watch(mediaRepositoryProvider),
      discovery: MethodChannelMediaDiscovery(),
      contentAccess: MethodChannelContentAccess(),
    );
  },
);

/// One pipeline shared by every surface that triggers or observes indexing.
final indexingCoordinatorProvider = Provider<IndexingCoordinator>((ref) {
  final documents = ref.watch(documentCoordinatorProvider);
  final ocr = ref.watch(ocrCoordinatorProvider);
  final semantic = ref.watch(semanticIndexCoordinatorProvider);
  final visual = ref.watch(visualIndexCoordinatorProvider);
  return IndexingCoordinator(
    mediaSync: _SynchronizationStage(
      ref.watch(synchronizationCoordinatorProvider),
    ),
    runDocuments: documents.start,
    cancelDocuments: documents.cancel,
    documentProgress: documents.progress,
    runOcr: ocr.start,
    cancelOcr: ocr.cancel,
    ocrProgress: ocr.progress,
    runSemantic: semantic?.run,
    cancelSemantic: semantic?.cancel,
    runVisual: visual?.run,
    cancelVisual: visual?.cancel,
    mediaStats: () => ref.read(mediaRepositoryProvider).stats(),
  );
});

/// The latest pipeline snapshot. Stays in [AsyncLoading] until the first run
/// emits, which the UI renders as "no indexing activity" (never an error).
final indexingStatusProvider = StreamProvider<IndexingStatus>((ref) {
  return ref.watch(indexingCoordinatorProvider).status;
});
