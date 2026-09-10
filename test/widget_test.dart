import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/app/app.dart';
import 'package:vorafind/core/constants/app_info.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: VoraFindApp()));
  }

  testWidgets('application boots without exceptions', (tester) async {
    await pumpApp(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('home shell renders VoraFind branding', (tester) async {
    await pumpApp(tester);

    expect(find.text(AppInfo.name), findsOneWidget);
    expect(find.text(AppInfo.tagline), findsOneWidget);
  });

  testWidgets('home shell exposes the dark theme', (tester) async {
    await pumpApp(tester);

    final context = tester.element(find.byType(Scaffold));
    final brightness = Theme.of(context).brightness;
    expect(brightness, Brightness.dark);
  });

  testWidgets('home shell communicates principles without fake features', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Local-first'), findsOneWidget);
    expect(find.text('Offline-first'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text(AppInfo.privacyStatement), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
