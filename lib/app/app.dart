import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/home/home_screen.dart';

/// Root widget of the VoraFind application.
///
/// VoraFind is dark-first, so the foundation ships a single dark theme.
/// The application shell is a single screen until real navigation has a
/// concrete requirement.
class VoraFindApp extends StatelessWidget {
  const VoraFindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoraFind',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
