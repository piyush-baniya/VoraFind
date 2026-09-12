import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';

/// Quiet, centered story state: icon, headline, and a short caption. Used for
/// empty and initial states across tabs so the language stays consistent.
class VoraEmptyState extends StatelessWidget {
  const VoraEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.caption,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? caption;
  final Widget? action;

@override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Icon(icon, size: 44, color: context.vora.textTertiary),
      const SizedBox(height: VoraSpace.lg),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ];
    if (caption != null) {
      children
        ..add(const SizedBox(height: VoraSpace.sm))
        ..add(
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.vora.textSecondary,
            ),
          ),
        );
    }
    if (action != null) {
      children
        ..add(const SizedBox(height: VoraSpace.xl))
        ..add(action!);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: VoraSpace.xl2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

/// Slim centered spinner used while a view loads real data. Never shows fake
/// progress — an indeterminate ring is honest when the pipeline has no
/// fraction to report.
class VoraLoadingView extends StatelessWidget {
  const VoraLoadingView({super.key, this.strokeWidth = 2.5});

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: strokeWidth),
      ),
    );
  }
}

/// Shared section heading (e.g. "Recent", "Settings").
class VoraSectionHeader extends StatelessWidget {
  const VoraSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, VoraSpace.sm, 4, VoraSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One row in a settings sheet: leading icon, title, subtitle, and a custom
/// trailing (chevron, switch, etc.). Consistent tap target and spacing.
class VoraSettingsTile extends StatelessWidget {
  const VoraSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _tileIcon(context),
      title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VoraRadius.md),
      ),
    );
  }

  Widget _tileIcon(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.vora.accentSubtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox.square(
        dimension: 36,
        child: Icon(icon, color: context.vora.accent, size: VoraIconSize.md),
      ),
    );
  }
}
