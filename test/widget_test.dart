import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/app/app.dart';
import 'package:vorafind/core/constants/app_info.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/media_repository.dart';
import 'package:vorafind/core/database/providers.dart';
import 'package:vorafind/core/database/synchronization_coordinator.dart';
import 'package:vorafind/core/documents/document_coordinator.dart';
import 'package:vorafind/core/documents/document_models.dart';
import 'package:vorafind/core/indexing/indexing_coordinator.dart';
import 'package:vorafind/core/indexing/indexing_providers.dart';
import 'package:vorafind/core/ocr/ocr_coordinator.dart';
import 'package:vorafind/core/ocr/ocr_models.dart';
import 'package:vorafind/core/platform/content_access_models.dart';
import 'package:vorafind/core/semantic/embedding_provider.dart';
import 'package:vorafind/core/semantic/semantic_providers.dart';

void main() {
  Future<ProviderContainer> newContainer() async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        // Hermetic widget tests: platform-channel futures never complete in
        // the FakeAsync test environment, so a real pipeline would leave the
        // status spinner pumping forever and time out pumpAndSettle. The
        // pipeline itself is covered by
        // test/indexing/indexing_coordinator_test.dart.
        indexingCoordinatorProvider.overrideWith((ref) => _IdlePipeline()),
        // The production embedding model loads long-running assets + native
        // inference on a real event loop; the search stage awaits the query
        // embedding, which would never resolve under FakeAsync. The
        // deterministic provider resolves each embed via microtasks so the
        // semantic path stays exercised without host/asset/native I/O.
        embeddingProvider.overrideWithValue(
          const DeterministicEmbeddingProvider(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const VoraFindApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('application boots without exceptions', (tester) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    expect(tester.takeException(), isNull);
  });

  testWidgets('search surface renders VoraFind branding and a search field', (
    tester,
  ) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    expect(find.text(AppInfo.name), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search your device'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget); // bottom-nav destination
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('application exposes the dark theme by default', (tester) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets('idle state reports an empty index honestly', (tester) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    // Empty index → honest onboarding instead of pretend results.
    expect(find.text('Nothing indexed yet'), findsOneWidget);
    expect(find.text('Give access'), findsOneWidget);
  });

  testWidgets('a search with no matches shows the no-results state', (
    tester,
  ) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    await tester.enterText(find.byType(TextField), 'zebra-photo-99');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('No files matched'), findsOneWidget);
  });

  testWidgets('switching to the light appearance rebuilds the theme', (
    tester,
  ) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.light);
  });

  testWidgets('Explore shows the browse chip row and a grid for images', (
    tester,
  ) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsWidgets);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
  });

  testWidgets('filtering a search by type shows the active filter chip', (
    tester,
  ) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    await tester.tap(find.byTooltip('Filter by type'));
    await tester.pumpAndSettle();
    expect(find.text('Filter by type'), findsOneWidget);

    await tester.tap(find.text('Images'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('images'), findsWidgets); // active filter chip label
  });
}

/// Media-sync stage that concludes instantly without touching channels.
class _NoSync implements IndexingMediaSync {
  const _NoSync();

  @override
  Future<SyncSessionResult> run(List<ContentCategory> categories) async =>
      const SyncSessionResult(outcome: SyncSessionOutcome.completed, units: []);

  @override
  Future<void> cancel() async {}
}

/// Inert pipeline: never starts, never emits. Widget tests exercise only UI
/// states; the pipeline itself is covered by
/// test/indexing/indexing_coordinator_test.dart and platform-channel futures
/// never complete inside the FakeAsync widget-test environment.
class _IdlePipeline extends IndexingCoordinator {
  _IdlePipeline()
    : super(
        mediaSync: const _NoSync(),
        runDocuments: () async =>
            const DocumentRunSummary(status: DocumentRunStatus.completed),
        cancelDocuments: () {},
        documentProgress: const Stream<DocumentRunProgress>.empty(),
        runOcr: () async => const OcrRunSummary(status: OcrRunStatus.completed),
        cancelOcr: () {},
        ocrProgress: const Stream<OcrRunProgress>.empty(),
        mediaStats: () async =>
            const MediaIndexStats(total: 0, byCategory: {}, volumeCount: 0),
      );

  @override
  Future<IndexingStatus> start() async => const IndexingStatus.idle();
}
