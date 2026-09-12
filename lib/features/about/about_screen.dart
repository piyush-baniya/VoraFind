import 'package:flutter/material.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../legal/privacy_screen.dart';
import '../legal/terms_screen.dart';
import '../shared/widgets/vora_surfaces.dart';

/// About VoraFind: identity, version, and the third-party notices entry point.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          VoraSpace.xl,
          VoraSpace.lg,
          VoraSpace.xl,
          VoraSpace.xl,
        ),
        children: [
          _BrandBlock(),
          const SizedBox(height: VoraSpace.xxl),
          _InfoCard(),
        ],
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.vora.accentSubtle,
            borderRadius: BorderRadius.circular(VoraRadius.lg),
            border: Border.all(color: context.vora.accentRing),
          ),
          child: SizedBox.square(
            dimension: 72,
            child: Icon(
              Icons.search_rounded,
              color: context.vora.accent,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: VoraSpace.lg),
        Text(AppInfo.name, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: VoraSpace.xs),
        Text(
          AppInfo.tagline,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: context.vora.textSecondary),
        ),
        const SizedBox(height: VoraSpace.md),
        Text(
          'Version ${AppInfo.version} (build ${AppInfo.buildNumber})',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.vora.textTertiary),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
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
        padding: const EdgeInsets.symmetric(vertical: VoraSpace.sm),
        child: Column(
          children: [
            VoraSettingsTile(
              icon: Icons.shield_outlined,
              title: 'Privacy Policy',
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const PrivacyScreen()),
            ),
            VoraSettingsTile(
              icon: Icons.receipt_long_outlined,
              title: 'Terms',
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const TermsScreen()),
            ),
            VoraSettingsTile(
              icon: Icons.workspace_premium_outlined,
              title: 'Open source licenses',
              subtitle: 'Packages and on-device models',
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppInfo.name,
                applicationVersion: AppInfo.version,
                applicationLegalese: AppInfo.privacyStatement,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}
