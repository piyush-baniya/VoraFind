/// Typed failure space for search.
abstract final class SearchErrorCode {
  static const database = 'database';
  static const invalidQuery = 'invalidQuery';
  static const cancelled = 'cancelled';
}

/// User-safe search error.
///
/// Mirrors the project's platform-error convention: a stable [code] plus a
/// message that never contains file names, paths, or user query text. Raw
/// Drift/SQL errors are mapped here at the repository boundary so the UI only
/// ever sees this type.
class SearchException implements Exception {
  const SearchException(this.code, this.message);

  /// A database/Drift failure while reading candidates.
  const SearchException.database([String? detail])
    : code = SearchErrorCode.database,
      message = detail == null
          ? 'The local index could not be read.'
          : 'The local index could not be read ($detail).';

  /// The query itself was invalid (e.g. inverted numeric ranges).
  const SearchException.invalidQuery([String? detail])
    : code = SearchErrorCode.invalidQuery,
      message = detail == null
          ? 'That search could not be understood.'
          : 'That search could not be understood ($detail).';

  /// The search was superseded or cancelled before completing. Not surfaced to
  /// the user as an error in normal flow.
  const SearchException.cancelled()
    : code = SearchErrorCode.cancelled,
      message = 'The search was cancelled.';

  final String code;
  final String message;

  @override
  String toString() => 'SearchException($code): $message';
}
