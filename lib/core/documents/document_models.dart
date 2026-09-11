import 'package:drift/drift.dart' show TypeConverter;

/// Durable access of a SAF grant or document row.
///
/// Revoking a tree permission marks rows [inaccessible]; it is not treated as
/// deletion. Confirmed absence from a completed, non-truncated enumeration is
/// what authorizes cleanup.
enum DocumentAccessState { accessible, inaccessible }

class DocumentAccessStateConverter
    extends TypeConverter<DocumentAccessState, String> {
  const DocumentAccessStateConverter();

  @override
  String toSql(DocumentAccessState value) => value.name;

  @override
  DocumentAccessState fromSql(String fromDb) =>
      DocumentAccessState.values.asNameMap()[fromDb] ??
      DocumentAccessState.inaccessible;
}

/// Durable extraction outcome for one document. Runtime-only states
/// (pending / processing / cancelled) are never persisted — an absent
/// `document_content` row means the document is still pending.
enum DocumentContentStatus {
  /// Text was extracted (may be truncated).
  completed,

  /// The parser ran and found no extractable text (typical of scanned PDFs).
  empty,

  /// Transient failure; retried after cooldown.
  failed,

  /// Permanent skip (unsupported type, encrypted, too large, unreadable).
  unsupported,
}

class DocumentContentStatusConverter
    extends TypeConverter<DocumentContentStatus, String> {
  const DocumentContentStatusConverter();

  @override
  String toSql(DocumentContentStatus value) => value.name;

  @override
  DocumentContentStatus fromSql(String fromDb) =>
      DocumentContentStatus.values.asNameMap()[fromDb] ??
      DocumentContentStatus.failed;
}

/// Runtime lifecycle of one coordinator run (never persisted).
enum DocumentRunStatus { idle, running, completed, failed, cancelled, paused }

/// Wire error codes from `vorafind/documents`.
enum DocumentErrorCode {
  uriUnavailable,
  tooLarge,
  encrypted,
  parseFailed,
  unsupportedType,
  busy,
  invalidArguments,
  inaccessible,
  platformUnavailable,
  unknown;

  static DocumentErrorCode fromWire(String? code) {
    if (code == null) return DocumentErrorCode.unknown;
    return DocumentErrorCode.values.asNameMap()[code] ??
        DocumentErrorCode.unknown;
  }
}

/// One discovered SAF document (metadata only — never bytes).
class DiscoveredDocument {
  const DiscoveredDocument({
    required this.stableKey,
    required this.treeUri,
    required this.documentId,
    required this.uri,
    required this.displayName,
    this.mimeType,
    this.sizeBytes,
    this.dateModified,
    this.relativePath,
  });

  factory DiscoveredDocument.fromJson(Map<String, dynamic> json) =>
      DiscoveredDocument(
        stableKey: json['stableKey'] as String,
        treeUri: json['treeUri'] as String,
        documentId: json['documentId'] as String,
        uri: json['uri'] as String,
        displayName: json['displayName'] as String,
        mimeType: json['mimeType'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        dateModified: (json['dateModified'] as num?)?.toInt(),
        relativePath: json['relativePath'] as String?,
      );

  final String stableKey;
  final String treeUri;
  final String documentId;
  final String uri;
  final String displayName;
  final String? mimeType;
  final int? sizeBytes;
  final int? dateModified;
  final String? relativePath;

  /// Metadata fingerprint used to detect content staleness without hashing
  /// file bytes. Size + last-modified + MIME can miss in-place edits that
  /// keep both values; that limitation is documented in `docs/documents.md`.
  String get contentFingerprint =>
      '${sizeBytes ?? ''}|${dateModified ?? ''}|${mimeType ?? ''}';
}

class DocumentEnumerationResult {
  const DocumentEnumerationResult({
    required this.documents,
    required this.inaccessible,
    required this.truncated,
  });

  factory DocumentEnumerationResult.fromJson(Map<String, dynamic> json) =>
      DocumentEnumerationResult(
        documents: ((json['documents'] as List<dynamic>?) ?? const [])
            .map(
              (entry) => DiscoveredDocument.fromJson(
                (entry as Map).cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
        inaccessible: json['inaccessible'] as bool? ?? false,
        truncated: json['truncated'] as bool? ?? false,
      );

  final List<DiscoveredDocument> documents;
  final bool inaccessible;
  final bool truncated;
}

class DocumentExtractionResult {
  const DocumentExtractionResult({
    required this.text,
    required this.truncated,
    required this.empty,
  });

  final String text;
  final bool truncated;
  final bool empty;
}

class DocumentExtractionException implements Exception {
  const DocumentExtractionException({required this.code, this.message});

  final DocumentErrorCode code;
  final String? message;

  @override
  String toString() =>
      'DocumentExtractionException(${code.name}${message == null ? '' : ': $message'})';
}

/// Defaults for the document pipeline (`docs/documents.md`).
abstract final class DocumentDefaults {
  static const int retryCooldownSeconds = 60 * 60;
  static const int extractionBatchSize = 20;
  static const int maxIndexedChars = 200000;
  static const int maxPdfBytes = 32 * 1024 * 1024;
  static const int maxTreeDepth = 8;
  static const int maxDocumentsPerTree = 5000;
  static const int enumerationPageHint = 100;

  static const List<String> supportedMimeTypes = [
    'application/pdf',
    'text/plain',
    'text/markdown',
    'text/x-markdown',
  ];
}
