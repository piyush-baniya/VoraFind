import 'package:flutter/services.dart';

import 'document_models.dart';

/// Native SAF enumeration and local document-text extraction.
///
/// Application code depends on this interface instead of the method channel.
abstract interface class DocumentPlatform {
  Future<DocumentEnumerationResult> enumerateDocumentTree({
    required String treeUri,
    int maxDepth = DocumentDefaults.maxTreeDepth,
    int maxItems = DocumentDefaults.maxDocumentsPerTree,
  });

  Future<DocumentExtractionResult> extractDocumentText({
    required String contentUri,
    String? mimeType,
    int maxChars = DocumentDefaults.maxIndexedChars,
  });
}

class MethodChannelDocumentPlatform implements DocumentPlatform {
  MethodChannelDocumentPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'vorafind/documents';

  final MethodChannel _channel;

  @override
  Future<DocumentEnumerationResult> enumerateDocumentTree({
    required String treeUri,
    int maxDepth = DocumentDefaults.maxTreeDepth,
    int maxItems = DocumentDefaults.maxDocumentsPerTree,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'enumerateDocumentTree',
        {'treeUri': treeUri, 'maxDepth': maxDepth, 'maxItems': maxItems},
      );
      return DocumentEnumerationResult.fromJson(raw ?? const {});
    } on MissingPluginException {
      throw const DocumentExtractionException(
        code: DocumentErrorCode.platformUnavailable,
        message: 'Document indexing is not available on this platform.',
      );
    } on PlatformException catch (error) {
      throw DocumentExtractionException(
        code: DocumentErrorCode.fromWire(error.code),
        message: error.message,
      );
    }
  }

  @override
  Future<DocumentExtractionResult> extractDocumentText({
    required String contentUri,
    String? mimeType,
    int maxChars = DocumentDefaults.maxIndexedChars,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'extractDocumentText',
        {'contentUri': contentUri, 'mimeType': mimeType, 'maxChars': maxChars},
      );
      final text = (raw?['text'] as String?) ?? '';
      final truncated = raw?['truncated'] as bool? ?? false;
      return DocumentExtractionResult(
        text: text,
        truncated: truncated,
        empty: text.trim().isEmpty,
      );
    } on MissingPluginException {
      throw const DocumentExtractionException(
        code: DocumentErrorCode.platformUnavailable,
        message: 'Document extraction is not available on this platform.',
      );
    } on PlatformException catch (error) {
      throw DocumentExtractionException(
        code: DocumentErrorCode.fromWire(error.code),
        message: error.message,
      );
    }
  }
}
