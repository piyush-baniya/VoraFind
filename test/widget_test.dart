import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/app/app.dart';
import 'package:vorafind/core/constants/app_info.dart';
import 'package:vorafind/core/database/app_database.dart';
import 'package:vorafind/core/database/providers.dart';

void main() {
  Future<ProviderContainer> newContainer() async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
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

    expect(find.text(AppInfo.name), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search your phone…'), findsOneWidget);
  });

  testWidgets('application exposes the dark theme', (tester) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    final context = tester.element(find.byType(Scaffold));
    final brightness = Theme.of(context).brightness;
    expect(brightness, Brightness.dark);
  });

  testWidgets('idle state reports an empty index honestly', (tester) async {
    final container = await newContainer();
    await pumpApp(tester, container);

    expect(find.text('Nothing indexed yet'), findsOneWidget);
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
}
