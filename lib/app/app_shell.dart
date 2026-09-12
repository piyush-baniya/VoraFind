import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/indexing/indexing_providers.dart';
import '../features/explore/explore_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/settings_screen.dart';

/// VoraFind's application shell: three top-level tabs (Search, Explore,
/// Settings) rendered in an [IndexedStack] so each tab keeps its scroll and
/// search state while switching (design system §7).
///
/// Owns the [AppLifecycleListener] that drives background indexing — media
/// sync → documents → OCR → semantics → visuals — so the full local pipeline
/// runs in the foreground and pauses the moment the app hides (AGENTS.md §22).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(ref.read(indexingCoordinatorProvider).start()),
      onPause: () => ref.read(indexingCoordinatorProvider).cancel(),
    );
    // AppLifecycleListener.onResume does not fire on initial attach, so the
    // first indexing run is kicked once here; later runs are lifecycle-driven.
    // The coordinator is single-flight, so both triggers coexist safely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(indexingCoordinatorProvider).start());
      }
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [HomeScreen(), ExploreScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
