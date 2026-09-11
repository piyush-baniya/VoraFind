import '../platform/media_discovery_models.dart';
import 'media_repository.dart';

/// Result of one discovery → persistence run.
///
/// A run ends with exactly one of the scanner's terminal states, or with
/// `failed` when persistence itself failed. When [state] is `failed`,
/// [errorCode] and [errorMessage] describe a user-safe reason and
/// [failedBatchSequence] names the batch that could not be persisted.
class DiscoveryRunSummary {
  const DiscoveryRunSummary({
    required this.state,
    required this.batchesPersisted,
    required this.recordsPersisted,
    this.errorCode,
    this.errorMessage,
    this.failedBatchSequence,
  });

  final DiscoveryLifecycleState state;
  final int batchesPersisted;
  final int recordsPersisted;
  final String? errorCode;
  final String? errorMessage;
  final int? failedBatchSequence;
}

/// Consumes the existing scanner's bounded batches and persists them before
/// acknowledging.
///
/// This is the Flutter-side persistence half of the architecture:
///
/// ```text
/// existing DiscoveryEngine
///   → EventChannel batches
///     → this orchestrator (transactional Drift upsert)
///       → ACK existing batch
/// ```
///
/// Contract: a batch is acknowledged **only** after its SQLite transaction has
/// committed. On persistence failure the batch is never acknowledged and the
/// run fails loudly. Cancellation is honored by stopping after the current
/// batch's transaction finishes (committed or rolled back — never torn).
class DiscoveryPersistenceOrchestrator {
  const DiscoveryPersistenceOrchestrator({required this.repository});

  final MediaRepository repository;

  /// Drives [events] (the `MediaDiscovery.events()` stream) against the
  /// repository, acknowledging each batch through [ackBatch] (normally
  /// `MediaDiscovery.ackBatch`).
  ///
  /// Returns after a terminal event (`discoveryCompleted`,
  /// `discoveryCancelled`, `discoveryError`), after a persistence failure, or
  /// when the stream ends.
  Future<DiscoveryRunSummary> run({
    required Stream<DiscoveryEvent> events,
    required Future<bool> Function(int sequence) ackBatch,
  }) async {
    var batchesPersisted = 0;
    var recordsPersisted = 0;

    Future<DiscoveryRunSummary> failCore(
      String code,
      String message,
      int? sequence,
    ) => Future.value(
      DiscoveryRunSummary(
        state: DiscoveryLifecycleState.failed,
        batchesPersisted: batchesPersisted,
        recordsPersisted: recordsPersisted,
        errorCode: code,
        errorMessage: message,
        failedBatchSequence: sequence,
      ),
    );

    try {
      await for (final event in events) {
        switch (event) {
          case DiscoveryBatchEvent():
            try {
              final written = await repository.upsertBatch(
                event.records,
                generationAfter: event.generationAfter,
                accessScope: event.accessScope,
              );
              batchesPersisted += 1;
              recordsPersisted += written;

              final acked = await ackBatch(event.sequence);
              if (!acked) {
                return await failCore(
                  'ackRejected',
                  'The scanner rejected the ACK for batch ${event.sequence}.',
                  event.sequence,
                );
              }
            } catch (error) {
              return await failCore(
                'persistenceFailed',
                'Persisting a discovery batch failed'
                    ' (${error.runtimeType}). The batch was not acknowledged.',
                event.sequence,
              );
            }
          case DiscoveryCompletedEvent():
            return DiscoveryRunSummary(
              state: DiscoveryLifecycleState.completed,
              batchesPersisted: batchesPersisted,
              recordsPersisted: recordsPersisted,
            );
          case DiscoveryCancelledEvent():
            return DiscoveryRunSummary(
              state: DiscoveryLifecycleState.cancelled,
              batchesPersisted: batchesPersisted,
              recordsPersisted: recordsPersisted,
            );
          case DiscoveryErrorEvent():
            return DiscoveryRunSummary(
              state: DiscoveryLifecycleState.failed,
              batchesPersisted: batchesPersisted,
              recordsPersisted: recordsPersisted,
              errorCode: event.code,
              errorMessage: event.message,
            );
          case DiscoveryStartedEvent():
          case DiscoveryProgressEvent():
            break;
        }
      }
    } catch (error) {
      return failCore(
        'discoveryStreamError',
        'The discovery stream failed (${error.runtimeType}).',
        null,
      );
    }

    // The stream ended without a terminal event.
    return failCore(
      'discoveryInterrupted',
      'The discovery stream ended before a terminal event.',
      null,
    );
  }
}
