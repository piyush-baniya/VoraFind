import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart' show SafGrant;
import '../database/document_repository.dart';
import '../database/providers.dart';
import '../platform/content_access.dart';
import 'document_coordinator.dart';
import 'document_platform.dart';

final contentAccessProvider = Provider<ContentAccess>((ref) {
  return MethodChannelContentAccess();
});

final documentPlatformProvider = Provider<DocumentPlatform>((ref) {
  return MethodChannelDocumentPlatform();
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DriftDocumentRepository(ref.watch(databaseProvider));
});

final documentCoordinatorProvider = Provider<DocumentCoordinator>((ref) {
  return DocumentCoordinator(
    repository: ref.watch(documentRepositoryProvider),
    contentAccess: ref.watch(contentAccessProvider),
    platform: ref.watch(documentPlatformProvider),
  );
});

final documentRunProgressProvider = StreamProvider<DocumentRunProgress>((ref) {
  return ref.watch(documentCoordinatorProvider).progress;
});

final documentGrantsProvider = FutureProvider<List<SafGrant>>((ref) {
  return ref.watch(documentRepositoryProvider).listGrants();
});

final documentStatsProvider = FutureProvider<DocumentIndexStats>((ref) {
  return ref.watch(documentRepositoryProvider).stats();
});
