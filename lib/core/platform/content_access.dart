import 'package:flutter/services.dart';

import 'content_access_models.dart';

/// Typed entry point to VoraFind's native Android content-access layer.
///
/// Application code depends on this interface instead of touching method
/// channel wire strings directly.
abstract interface class ContentAccess {
  /// Snapshot of what VoraFind can access right now. Side-effect free.
  Future<ContentCapabilities> getCapabilities();

  /// Current access state for [category]. Side-effect free: never shows a
  /// dialog or opens a picker.
  Future<ContentCategoryAccess> getPermissionState(ContentCategory category);

  /// Requests media access for [category] (images, videos, audio) and returns
  /// the resulting state. Rejects documents, which are granted via
  /// [requestDocumentTree] instead.
  Future<ContentCategoryAccess> requestMediaAccess(ContentCategory category);

  /// Opens the Android folder picker. Returns [DocumentGrantResult.cancelled]
  /// == true when the user cancels.
  Future<DocumentGrantResult> requestDocumentTree();

  /// Currently valid persisted document-tree grants (revoked grants excluded).
  Future<List<DocumentGrant>> listDocumentTreeGrants();

  /// Releases a persisted read grant for [uri]. Returns false if nothing was
  /// released.
  Future<bool> releaseDocumentTreeGrant(String uri);
}

/// [ContentAccess] backed by the `vorafind/content_access` method channel.
class MethodChannelContentAccess implements ContentAccess {
  MethodChannelContentAccess({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(contentAccessChannelName);

  /// Dart side of the `vorafind/content_access` method channel declared by
  /// [ContentAccessBridge] (Kotlin).
  static const contentAccessChannelName = 'vorafind/content_access';

  final MethodChannel _channel;

  @override
  Future<ContentCapabilities> getCapabilities() => _invoke(
    'getCapabilities',
    null,
    (raw) => ContentCapabilities.fromJson(_mapOf(raw)),
  );

  @override
  Future<ContentCategoryAccess> getPermissionState(ContentCategory category) =>
      _invoke('getPermissionState', {
        'category': category.name,
      }, (raw) => ContentCategoryAccess.fromJson(_mapOf(raw)));

  @override
  Future<ContentCategoryAccess> requestMediaAccess(ContentCategory category) {
    if (category == ContentCategory.documents) {
      throw ArgumentError.value(
        category,
        'category',
        'Documents are granted through the folder picker, not a permission request.',
      );
    }
    return _invoke('requestMediaAccess', {
      'category': category.name,
    }, (raw) => ContentCategoryAccess.fromJson(_mapOf(raw)));
  }

  @override
  Future<DocumentGrantResult> requestDocumentTree() => _invoke(
    'requestDocumentTree',
    null,
    (raw) => DocumentGrantResult.fromJson(_mapOf(raw)),
  );

  @override
  Future<List<DocumentGrant>> listDocumentTreeGrants() => _invoke(
    'listDocumentTreeGrants',
    null,
    (raw) => (raw as List<dynamic>)
        .map(
          (entry) =>
              DocumentGrant.fromJson((entry as Map).cast<String, dynamic>()),
        )
        .toList(growable: false),
  );

  @override
  Future<bool> releaseDocumentTreeGrant(String uri) =>
      _invoke('releaseDocumentTreeGrant', {'uri': uri}, (raw) => raw as bool);

  Future<T> _invoke<T>(
    String method,
    Map<String, Object?>? arguments,
    T Function(Object?) decode,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, arguments);
      return decode(raw);
    } on PlatformException catch (error) {
      throw ContentAccessException.fromPlatformException(error);
    }
  }

  Map<String, dynamic> _mapOf(Object? raw) =>
      (raw as Map).cast<String, dynamic>();
}
