import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_info.dart';
import '../../core/database/media_repository.dart' show MediaIndexStats;
import '../../core/database/document_repository.dart' show DocumentIndexStats;
import '../../core/documents/document_providers.dart'
    show contentAccessProvider, documentStatsProvider;
import '../../core/platform/content_access_models.dart'
    show ContentCapabilities, ContentCategory;
import '../../core/search/search_providers.dart' show indexStatsProvider;
import '../../core/settings/app_settings_providers.dart';
import '../../core/settings/settings_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../features/about/about_screen.dart';
import '../../features/legal/privacy_screen.dart';
import '../../features/legal/terms_screen.dart';
import '../shared/widgets/vora_surfaces.dart';

/// Settings tab: appearance, local index overview, and legal/info surfaces.
///
/// Every control is real: appearance persists locally via [themePreferenceProvider]
/// (Drift, no backend, no account). Indexed-content numbers come from the live
/// media and document stats — no fake toggles or decorative counters.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          VoraSpace.lg,
          VoraSpace.lg,
          VoraSpace.lg,
          VoraSpace.xl,
        ),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: VoraSpace.lg),
          const _SurfaceCard(child: _AppearanceSection()),
          const SizedBox(height: VoraSpace.lg),
          const _SurfaceCard(child: _IndexSection()),
          const SizedBox(height: VoraSpace.lg),
          const _SurfaceCard(child: _AboutSection()),
          const SizedBox(height: VoraSpace.lg),
          Text(
            AppInfo.privacyStatement,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.vora.textTertiary),
          ),
          const SizedBox(height: VoraSpace.sm),
        ],
      ),
    );
  }
}

/// Shared grouped-surface container for settings sections.
class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.vora.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VoraRadius.lg),
        side: BorderSide(color: context.vora.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VoraSpace.sm,
          vertical: VoraSpace.sm,
        ),
        child: child,
      ),
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themePreferenceProvider);
    final notifier = ref.read(themePreferenceProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VoraSectionHeader(title: 'Appearance'),
        RadioGroup<AppThemePreference>(
          groupValue: mode,
          onChanged: (value) {
            if (value != null) notifier.setMode(value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in AppThemePreference.values)
                RadioListTile<AppThemePreference>(
                  value: option,
                  title: Text(option.label),
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(VoraRadius.md),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IndexSection extends ConsumerWidget {
  const _IndexSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(indexStatsProvider);
    final documents = ref.watch(documentStatsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VoraSectionHeader(title: 'Indexed content'),
        stats.maybeWhen(
          data: (media) => _IndexRows(mediaStats: media),
          orElse: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: VoraSpace.sm),
            child: VoraLoadingView(strokeWidth: 2),
          ),
        ),
        const Divider(height: VoraSpace.md),
        documents.maybeWhen(
          data: (docs) => _DocumentRows(docs: docs),
          orElse: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: VoraSpace.sm),
            child: VoraLoadingView(strokeWidth: 2),
          ),
        ),
        const SizedBox(height: VoraSpace.xs),
        _AccessLine(),
      ],
    );
  }
}

/// One media-category count shared by the grid + the total.
class _IndexRows extends StatelessWidget {
  const _IndexRows({required this.mediaStats});

  final MediaIndexStats mediaStats;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: VoraSpace.sm,
      runSpacing: VoraSpace.sm,
      children: [
        for (final category in ContentCategory.values)
          _CountChip(
            label: _mediaCountLabel(category),
            count: mediaStats.countOf(category),
          ),
      ],
    );
  }

  static String _mediaCountLabel(ContentCategory category) =>
      switch (category) {
        ContentCategory.images => 'Images',
        ContentCategory.videos => 'Videos',
        ContentCategory.audio => 'Audio',
        ContentCategory.documents => 'Documents',
      };
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VoraSpace.md,
        vertical: VoraSpace.sm,
      ),
      decoration: BoxDecoration(
        color: context.vora.surfaceElevated,
        borderRadius: BorderRadius.circular(VoraRadius.md),
        border: Border.all(color: context.vora.divider),
      ),
      child: Text(
        '$label  $count',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _DocumentRows extends StatelessWidget {
  const _DocumentRows({required this.docs});

  final DocumentIndexStats docs;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: VoraSpace.sm,
      runSpacing: VoraSpace.sm,
      children: [
        _CountChip(label: 'Documents', count: docs.total),
        _CountChip(label: 'Text extracted', count: docs.completed),
      ],
    );
  }
}

/// Honest access readout: what MediaStore/SAF currently allows, derived from
/// the platform's own capabilities (never assumed).
class _AccessLine extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(_capabilitiesProvider);
    return caps.maybeWhen(
      data: (capabilities) => _capabilitiesRow(context, capabilities),
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _capabilitiesRow(
    BuildContext context,
    ContentCapabilities capabilities,
  ) {
    final parts = <String>[];
    for (final category in ContentCategory.values) {
      final access = capabilities.accessFor(category);
      parts.add(
        '${_mediaCountLabel(category)}: ${_stateLabel(access.state.name)}',
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: VoraSpace.sm),
      child: Text(
        parts.join(' · '),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.vora.textSecondary),
      ),
    );
  }

  static String _mediaCountLabel(ContentCategory category) =>
      switch (category) {
        ContentCategory.images => 'Photos',
        ContentCategory.videos => 'Videos',
        ContentCategory.audio => 'Audio',
        ContentCategory.documents => 'Files',
      };

  static String _stateLabel(String state) => switch (state) {
    'fullAccess' => 'full',
    'partialAccess' => 'partial',
    'permanentlyDenied' => 'denied',
    'noAccess' => 'none',
    'denied' => 'denied',
    _ => 'none',
  };
}

final _capabilitiesProvider = FutureProvider<ContentCapabilities>((ref) {
  return ref.watch(contentAccessProvider).getCapabilities();
});

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VoraSectionHeader(title: 'About'),
        VoraSettingsTile(
          icon: Icons.shield_outlined,
          title: 'Privacy Policy',
          subtitle: 'Read how your content stays on this device.',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _push(context, const PrivacyScreen()),
        ),
        VoraSettingsTile(
          icon: Icons.receipt_long_outlined,
          title: 'Terms',
          subtitle: 'The rules for using VoraFind.',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _push(context, const TermsScreen()),
        ),
        VoraSettingsTile(
          icon: Icons.copyright_outlined,
          title: 'About VoraFind',
          subtitle: 'Version ${AppInfo.version}',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _push(context, const AboutScreen()),
        ),
      ],
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}
