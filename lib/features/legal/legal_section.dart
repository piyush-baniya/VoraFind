import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Shared spacing/typography for local legal documents (Privacy, Terms).
class LegalHeading extends StatelessWidget {
  const LegalHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: VoraSpace.lg, bottom: VoraSpace.sm),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class LegalParagraph extends StatelessWidget {
  const LegalParagraph(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VoraSpace.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
      ),
    );
  }
}

/// Shared page shell (scroll + padding) for legal documents.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          VoraSpace.xl,
          VoraSpace.md,
          VoraSpace.xl,
          VoraSpace.xl,
        ),
        children: children,
      ),
    );
  }
}
