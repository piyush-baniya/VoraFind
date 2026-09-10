import 'package:flutter/services.dart';

/// Category of user content VoraFind can eventually index.
///
/// Wire values match the Kotlin enum (ContentCategory); rename carefully.
enum ContentCategory {
  images,
  videos,
  audio,
  documents;

  static ContentCategory fromWire(String value) => values.firstWhere(
    (category) => category.name == value,
    orElse: () => throw FormatException('Unknown content category: $value'),
  );
}

/// How VoraFind can currently access a content category.
///
/// Wire values match the Kotlin enum (ContentAccessState); rename carefully.
enum ContentAccessState {
  notRequired,
  noAccess,
  denied,
  permanentlyDenied,
  fullAccess,
  partialAccess;

  static ContentAccessState fromWire(String value) => values.firstWhere(
    (state) => state.name == value,
    orElse: () => throw FormatException('Unknown content access state: $value'),
  );
}

/// Access description for one content category.
///
/// The three capabilities are derived exclusively from [state], so a partial
/// grant can never be mistaken for full library access (architecture §20).
class ContentCategoryAccess {
  const ContentCategoryAccess({required this.category, required this.state});

  factory ContentCategoryAccess.fromJson(Map<String, dynamic> json) =>
      ContentCategoryAccess(
        category: ContentCategory.fromWire(json['category'] as String),
        state: ContentAccessState.fromWire(json['state'] as String),
      );

  final ContentCategory category;
  final ContentAccessState state;

  /// True when the platform allows querying this category at all.
  bool get canQuery =>
      state == ContentAccessState.fullAccess ||
      state == ContentAccessState.partialAccess ||
      state == ContentAccessState.notRequired;

  /// True only when the entire library of this category is readable.
  bool get canReadAll => state == ContentAccessState.fullAccess;

  /// True when a user-selected subset is readable (full access trivially
  /// includes the selected subset; partial access stops there).
  bool get canReadSelected =>
      state == ContentAccessState.fullAccess ||
      state == ContentAccessState.partialAccess;
}

/// Versioned, platform-friendly snapshot of what VoraFind can access now.
class ContentCapabilities {
  const ContentCapabilities({
    required this.contractVersion,
    required this.apiLevel,
    required this.safCapable,
    required this.mediaStoreGenerationSupported,
    required this.partialMediaAccessSupported,
    required this.externalVolumes,
    required this.categories,
  });

  factory ContentCapabilities.fromJson(
    Map<String, dynamic> json,
  ) => ContentCapabilities(
    contractVersion: json['contractVersion'] as int,
    apiLevel: json['apiLevel'] as int,
    safCapable: json['safCapable'] as bool,
    mediaStoreGenerationSupported:
        json['mediaStoreGenerationSupported'] as bool,
    partialMediaAccessSupported: json['partialMediaAccessSupported'] as bool,
    externalVolumes: (json['externalVolumes'] as List<dynamic>).cast<String>(),
    categories: (json['categories'] as List<dynamic>)
        .map(
          (entry) => ContentCategoryAccess.fromJson(
            (entry as Map).cast<String, dynamic>(),
          ),
        )
        .toList(growable: false),
  );

  final int contractVersion;
  final int apiLevel;
  final bool safCapable;
  final bool mediaStoreGenerationSupported;
  final bool partialMediaAccessSupported;
  final List<String> externalVolumes;
  final List<ContentCategoryAccess> categories;

  ContentCategoryAccess accessFor(ContentCategory category) =>
      categories.firstWhere((access) => access.category == category);
}

/// A SAF document-tree grant, safe to persist as metadata by the future
/// database layer.
class DocumentGrant {
  const DocumentGrant({
    required this.uri,
    required this.displayName,
    required this.persisted,
    required this.readable,
    required this.writable,
  });

  factory DocumentGrant.fromJson(Map<String, dynamic> json) => DocumentGrant(
    uri: json['uri'] as String,
    displayName: json['displayName'] as String,
    persisted: json['persisted'] as bool,
    readable: json['readable'] as bool,
    writable: json['writable'] as bool,
  );

  final String uri;
  final String displayName;
  final bool persisted;
  final bool readable;
  final bool writable;
}

/// Outcome of the folder picker. A cancelled picker carries no grant.
class DocumentGrantResult {
  const DocumentGrantResult({required this.cancelled, this.grant});

  factory DocumentGrantResult.fromJson(Map<String, dynamic> json) {
    final grant = json['grant'];
    return DocumentGrantResult(
      cancelled: json['cancelled'] as bool? ?? false,
      grant: grant == null
          ? null
          : DocumentGrant.fromJson((grant as Map).cast<String, dynamic>()),
    );
  }

  final bool cancelled;
  final DocumentGrant? grant;
}

/// User-safe error from the native content-access layer.
///
/// Codes mirror the Kotlin bridge: invalidArguments, pickUnavailable,
/// grantFailed, permissionRequestFailed, security, unknown.
class ContentAccessException implements Exception {
  const ContentAccessException(this.code, this.message);

  factory ContentAccessException.fromPlatformException(
    PlatformException error,
  ) => ContentAccessException(error.code, error.message ?? error.code);

  final String code;
  final String message;

  @override
  String toString() => 'ContentAccessException($code): $message';
}
