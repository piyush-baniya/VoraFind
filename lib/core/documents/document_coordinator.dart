import 'dart:async';

import '../database/document_repository.dart';
import '../platform/content_access.dart';
import 'document_models.dart';
import 'document_platform.dart';

class DocumentRunProgress {
  const DocumentRunProgress({
    required this.status,
    required this.processed,
    required this.total,
    required this.succeeded,
    required this.failed,
  });

  final DocumentRunStatus status;
  final int processed;
  final int total;
  final int succeeded;
  final int failed;

  double get fraction => total == 0 ? 1 : (processed / total).clamp(0.0, 1.0);
}

class DocumentRunSummary {
  const DocumentRunSummary({
    required this.status,
    this.processed = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.errorMessage,
  });

  final DocumentRunStatus status;
  final int processed;
  final int succeeded;
  final int failed;
  final String? errorMessage;
}

/// Discovers granted SAF documents and extracts local text in bounded batches.
///
/// Discovery (metadata) always precedes extraction. Search never opens PDFs.
class DocumentCoordinator {
  DocumentCoordinator({
    required this.repository,
    required this.contentAccess,
    required this.platform,
    this.batchSize = DocumentDefaults.extractionBatchSize,
    this.nowSeconds,
  });

  final DocumentRepository repository;
  final ContentAccess contentAccess;
  final DocumentPlatform platform;
  final int batchSize;
  final int Function()? nowSeconds;

  final StreamController<DocumentRunProgress> _progress =
      StreamController<DocumentRunProgress>.broadcast();

  Stream<DocumentRunProgress> get progress => _progress.stream;

  bool _running = false;
  bool _cancelRequested = false;
  DocumentRunProgress? _last;

  bool get isRunning => _running;
  DocumentRunProgress? get lastProgress => _last;

  int _now() => (nowSeconds ?? _defaultNowSeconds)();

  Future<DocumentRunSummary> start() async {
    if (_running) {
      return const DocumentRunSummary(status: DocumentRunStatus.running);
    }

    _running = true;
    _cancelRequested = false;
    var processed = 0;
    var succeeded = 0;
    var failed = 0;
    var total = 0;
    try {
      await _syncGrantsAndDiscover();
      if (_cancelRequested) {
        return _finish(
          status: DocumentRunStatus.cancelled,
          processed: processed,
          total: total,
          succeeded: succeeded,
          failed: failed,
        );
      }

      total = (await repository.stats()).accessible;
      _emit(DocumentRunStatus.running, processed, total, succeeded, failed);

      while (!_cancelRequested) {
        final candidates = await repository.findExtractionCandidates(
          batchSize: batchSize,
          nowEpochSeconds: _now(),
        );
        if (candidates.isEmpty) break;
        for (final candidate in candidates) {
          if (_cancelRequested) break;
          if (await _extractOne(
            candidate.stableKey,
            candidate.uri,
            candidate.mimeType,
            candidate.sourceRevision,
          )) {
            succeeded++;
          } else {
            failed++;
          }
          processed++;
        }
        _emit(DocumentRunStatus.running, processed, total, succeeded, failed);
      }

      final status = _cancelRequested
          ? DocumentRunStatus.cancelled
          : DocumentRunStatus.completed;
      return _finish(
        status: status,
        processed: processed,
        total: total,
        succeeded: succeeded,
        failed: failed,
      );
    } catch (error) {
      return _finish(
        status: DocumentRunStatus.failed,
        processed: processed,
        total: total,
        succeeded: succeeded,
        failed: failed,
        errorMessage: 'Document indexing failed (${error.runtimeType}).',
      );
    } finally {
      _running = false;
    }
  }

  void cancel() {
    _cancelRequested = true;
  }

  Future<void> _syncGrantsAndDiscover() async {
    final now = _now();
    final liveGrants = await contentAccess.listDocumentTreeGrants();
    final liveUris = {for (final grant in liveGrants) grant.uri};

    for (final grant in liveGrants) {
      if (_cancelRequested) return;
      await repository.upsertGrant(grant, nowSeconds: now);
      await _enumerateGrant(grant.uri, now: now);
    }

    final known = await repository.listGrants();
    for (final grant in known) {
      if (_cancelRequested) return;
      if (!liveUris.contains(grant.treeUri)) {
        await repository.markGrantInaccessible(grant.treeUri, nowSeconds: now);
      }
    }
  }

  Future<void> _enumerateGrant(String treeUri, {required int now}) async {
    try {
      final result = await platform.enumerateDocumentTree(treeUri: treeUri);
      if (result.inaccessible) {
        await repository.markGrantInaccessible(treeUri, nowSeconds: now);
        return;
      }
      await repository.upsertDocuments(result.documents, nowSeconds: now);
      if (!result.truncated) {
        await repository.deleteMissingFromTree(
          treeUri: treeUri,
          seenKeys: {for (final doc in result.documents) doc.stableKey},
        );
      }
    } on DocumentExtractionException catch (error) {
      if (error.code == DocumentErrorCode.inaccessible ||
          error.code == DocumentErrorCode.uriUnavailable) {
        await repository.markGrantInaccessible(treeUri, nowSeconds: now);
        return;
      }
      rethrow;
    }
  }

  Future<bool> _extractOne(
    String stableKey,
    String contentUri,
    String? mimeType,
    int sourceRevision,
  ) async {
    try {
      final result = await platform.extractDocumentText(
        contentUri: contentUri,
        mimeType: mimeType,
      );
      final empty = result.text.trim().isEmpty;
      await repository.saveExtractionResult(
        stableKey: stableKey,
        text: result.text,
        status: empty
            ? DocumentContentStatus.empty
            : DocumentContentStatus.completed,
        sourceRevision: sourceRevision,
        nowEpochSeconds: _now(),
        truncated: result.truncated,
      );
      return true;
    } on DocumentExtractionException catch (error) {
      final status = _durableStatus(error.code);
      await repository.saveExtractionResult(
        stableKey: stableKey,
        text: null,
        status: status,
        sourceRevision: sourceRevision,
        nowEpochSeconds: _now(),
        errorCode: error.code.name,
      );
      return false;
    }
  }

  static DocumentContentStatus _durableStatus(DocumentErrorCode code) {
    switch (code) {
      case DocumentErrorCode.tooLarge:
      case DocumentErrorCode.encrypted:
      case DocumentErrorCode.unsupportedType:
      case DocumentErrorCode.parseFailed:
        return DocumentContentStatus.unsupported;
      case DocumentErrorCode.uriUnavailable:
      case DocumentErrorCode.inaccessible:
      case DocumentErrorCode.busy:
      case DocumentErrorCode.invalidArguments:
      case DocumentErrorCode.platformUnavailable:
      case DocumentErrorCode.unknown:
        return DocumentContentStatus.failed;
    }
  }

  DocumentRunSummary _finish({
    required DocumentRunStatus status,
    required int processed,
    required int total,
    required int succeeded,
    required int failed,
    String? errorMessage,
  }) {
    _emit(status, processed, total, succeeded, failed);
    return DocumentRunSummary(
      status: status,
      processed: processed,
      succeeded: succeeded,
      failed: failed,
      errorMessage: errorMessage,
    );
  }

  void _emit(
    DocumentRunStatus status,
    int processed,
    int total,
    int succeeded,
    int failed,
  ) {
    final snapshot = DocumentRunProgress(
      status: status,
      processed: processed,
      total: total,
      succeeded: succeeded,
      failed: failed,
    );
    _last = snapshot;
    _progress.add(snapshot);
  }

  static int _defaultNowSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
