import 'package:flutter/material.dart';

import '../../core/constants/app_info.dart';
import 'legal_section.dart';

/// VoraFind Privacy Policy — a plain-language local document.
///
/// Kept intentionally short and technically accurate; no invented URLs and no
/// claim of uploads anywhere (privacy rules §8).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPage(
      title: 'Privacy Policy',
      children: [
        LegalParagraph(
          '${AppInfo.name} is a local, offline-first search engine. '
          'By design: ${AppInfo.privacyStatement}',
        ),
        LegalHeading('What VoraFind stores'),
        LegalParagraph(
          'To search your content, VoraFind builds a local index in a '
          'SQLite database on this device. It stores file names and '
          'metadata, recognized text from images (OCR), text extracted from '
          'documents, semantic embeddings, and visual features. This derived '
          'data is separate from your original files.',
        ),
        LegalHeading('What leaves the device'),
        LegalParagraph(
          'Nothing. VoraFind has no account, no cloud sync, no analytics, '
          'and no internet back end. Your files, OCR text, thumbnails, and '
          'embeddings never leave this device. All model inference runs '
          'on-device.',
        ),
        LegalHeading('Permissions'),
        LegalParagraph(
          'VoraFind asks only for the access a feature genuinely needs: '
          'reading your media library to index it, and (only if you choose) '
          'a folder you grant for documents. You can revoke either in system '
          'settings at any time.',
        ),
        LegalHeading('Deletion'),
        LegalParagraph(
          'Uninstall the app or clear its data and the local index is '
          'removed; your original files are never modified or deleted.',
        ),
        LegalHeading('Contact'),
        LegalParagraph(
          'Questions? Contact us through the store listing where you '
          'downloaded ${AppInfo.name}.',
        ),
      ],
    );
  }
}
