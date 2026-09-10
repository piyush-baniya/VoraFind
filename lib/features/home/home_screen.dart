import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';

/// Initial VoraFind shell.
///
/// This screen establishes branding and communicates the product direction
/// without pretending that search or indexing already exist. It must render
/// correctly on small and large screens and remain lightweight.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _BrandMark(),
                  const SizedBox(height: 32),
                  Semantics(
                    header: true,
                    child: Text(
                      AppInfo.name,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppInfo.tagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 40),
                  const Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _PrincipleChip(
                        icon: Icons.storage_rounded,
                        label: 'Local-first',
                      ),
                      _PrincipleChip(
                        icon: Icons.offline_bolt_rounded,
                        label: 'Offline-first',
                      ),
                      _PrincipleChip(
                        icon: Icons.lock_outline_rounded,
                        label: 'Private',
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  Text(
                    AppInfo.privacyStatement,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded-square brand mark using the search glyph.
///
/// The accent block is intentionally the only saturated element on the
/// screen; the rest of the shell stays monochrome.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${AppInfo.name} logo',
      image: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.accentSubtle,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.accentRing),
        ),
        child: const SizedBox(
          width: 64,
          height: 64,
          child: Icon(Icons.search_rounded, color: AppColors.accent, size: 34),
        ),
      ),
    );
  }
}

/// Small pill describing one VoraFind principle.
class _PrincipleChip extends StatelessWidget {
  const _PrincipleChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
