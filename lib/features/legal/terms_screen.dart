import 'package:flutter/material.dart';

import '../../core/constants/app_info.dart';
import 'legal_section.dart';

/// VoraFind Terms of Use — concise local terms with no invented legal entity
/// or jurisdiction, since there is no cloud service attached.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPage(
      title: 'Terms',
      children: [
        LegalHeading('Using VoraFind'),
        LegalParagraph(
          '${AppInfo.name} is a local tool for searching content stored on '
          'your own device. You are responsible for the files you choose to '
          'index and for keeping your own backups.',
        ),
        LegalHeading('Your content'),
        LegalParagraph(
          'You retain all rights to your content. VoraFind does not upload, '
          'copy off-device, or claim any rights to your files.',
        ),
        LegalHeading('No warranty'),
        LegalParagraph(
          'VoraFind is provided "as is" without warranties of any kind. '
          'Search results and on-device analysis may be incomplete or '
          'inaccurate; always verify important information yourself.',
        ),
        LegalHeading('Acceptable use'),
        LegalParagraph(
          'Do not use VoraFind to access content you are not authorized to '
          'access, or in violation of applicable law.',
        ),
        LegalHeading('Changes'),
        LegalParagraph(
          'These terms may be updated as ${AppInfo.name} evolves. Continued '
          'use of the app after an update means you accept the revised terms.',
        ),
      ],
    );
  }
}
