import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'media_repository.dart';

/// The app's on-device Drift database. Lazy — nothing is opened or touched
/// until a UI or service actually reads this provider.
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.forApp();
  ref.onDispose(database.close);
  return database;
});

/// Durable media-index repository. UI code depends on this provider (never on
/// Drift tables directly).
final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return DriftMediaRepository(ref.watch(databaseProvider));
});
