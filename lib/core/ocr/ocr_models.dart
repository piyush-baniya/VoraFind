import 'package:drift/drift.dart' show TypeConverter;

/// Durable OCR state of one media row, persisted in `ocr_content.status`.
///
/// Only these three values are ever written to the database:
///
/// * [completed] — recognition succeeded (an empty string is a valid "no text
///   found" result, not an error).
/// * [failed] — *transient* failure (unreadable right now, permission revoked,
///   recognizer error). Eligible again after the retry cooldown, so a temporary
///   problem does not permanently burn battery or mark the row forever.
/// * [unsupported] — *permanent* failure (image data cannot be decoded at
///   all). Never retried automatically.
///
/// Whether a row still needs processing is not itself a stored value: an
/// absent `ocr_content` row means "pending". A hypothetical `pending`/running
/// column is deliberately avoided — a crash mid-run could leave a durable
/// "running" claim that blocks the row forever. In-progress work lives only in
/// the [OcrCoordinator]'s runtime state.
enum OcrStatus { completed, failed, unsupported }

/// Drift type converter for [OcrStatus], stored as the enum's `name`
/// (`'completed' | 'failed' | 'unsupported'`). Lives here so the table schema
/// (`ocr_content_table.dart`) references it by name and drift can generate the
/// mapping code.
class OcrStatusConverter extends TypeConverter<OcrStatus, String> {
  const OcrStatusConverter();

  @override
  String toSql(OcrStatus value) => value.name;

  @override
  OcrStatus fromSql(String fromDb) {
    return OcrStatus.values.asNameMap()[fromDb] ?? OcrStatus.failed;
  }
}

/// High-level lifecycle state of one coordinator run (runtime only — never
/// persisted). See AGENTS.md §18.
///
/// [paused] exists for forward compatibility but is not used today; the
/// coordinator currently exposes `idle | running | completed | failed |
/// cancelled`.
enum OcrRunStatus { idle, running, completed, failed, cancelled, paused }

/// Error code produced by the native `vorafind/ocr` bridge (or by the Dart
/// facade when the platform layer is unavailable).
enum OcrErrorCode {
  /// The content URI could not be opened (file gone, or permission revoked).
  uriUnavailable,

  /// Bytes were read but could not be decoded as an image at all.
  decodeFailed,

  /// The recognizer failed while processing a decodable image.
  ocrFailed,

  /// Another recognition call is still in flight (single-flight violation).
  busy,

  /// Arguments were invalid.
  invalidArguments,

  /// The platform channel was unavailable (e.g. MissingPluginException).
  platformUnavailable,

  /// A native code that this Dart version does not recognize.
  unknown;

  static OcrErrorCode fromWire(String? code) {
    if (code == null) return OcrErrorCode.unknown;
    return OcrErrorCode.values.asNameMap()[code] ?? OcrErrorCode.unknown;
  }
}

/// Result of one successful [OcrDetector.recognizeText] call.
class OcrRecognitionResult {
  const OcrRecognitionResult({required this.text});

  /// Raw recognized text (may be empty for an image with no text).
  final String text;
}

/// Failure of one recognition call, with a stable machine-readable [code].
class OcrRecognitionException implements Exception {
  const OcrRecognitionException({required this.code, this.message});

  final OcrErrorCode code;
  final String? message;

  @override
  String toString() =>
      'OcrRecognitionException(${code.name}${message == null ? '' : ': $message'})';
}
