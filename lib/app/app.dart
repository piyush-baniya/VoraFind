import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/app_settings_providers.dart';
import '../core/theme/app_theme.dart';
import 'app_shell.dart';

/// Root widget of the VoraFind application.
///
/// Ships both themes (deep dark for AMOLED plus a genuinely light one) and
/// follows [themePreferenceProvider] — System / Light / Dark, persisted
/// locally (Drift, no account, no sync). The application shell owns the three
/// top-level tabs (Search, Explore, Settings).
class VoraFindApp extends ConsumerWidget {
  const VoraFindApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themePreferenceProvider).themeMode;

    return MaterialApp(
      title: 'VoraFind',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 250),
      themeAnimationCurve: Curves.easeOutCubic,
      home: const AppShell(),
    );
  }
}
