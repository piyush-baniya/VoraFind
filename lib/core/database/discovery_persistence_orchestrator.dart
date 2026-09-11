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

/// Lifecycle hooks for a [DiscoveryStreamConsumer].
///
/// Every hook is optional. A failing hook aborts the run exactly like a
/// persistence failure — the affected batch is never acknowledged. Hooks are
/// awaited in order: `onStarted` before a unit's first batch, `onBatchPersisted`
/// after the batch committed and before it is acknowledged, and one terminal
/// hook (`onCompleted`/`onCancelled`/`onError`) when the session ends.
class DiscoveryStreamObserver {
  const DiscoveryStreamObserver({
    this.onStarted,
    this.onProgress,
    this.onBatchPersisted,
    this.onCompleted,
    this.onCancelled,
    this.onError,
  });

  /// A category/volume scan began (before its first batch).
  final Future<void> Function(DiscoveryStartedEvent event)? onStarted;

  final Future<void> Function(DiscoveryProgressEvent event)? onProgress;

  /// Fired after the batch committed to storage, before it is acknowledged.
  /// [written] is what [DiscoveryStreamConsumer.persistBatch] returned.
  final Future<void> Function(DiscoveryBatchEvent event, int written)?
  onBatchPersisted;

  final Future<void> Function(DiscoveryCompletedEvent event)? onCompleted;

  final Future<void> Function(DiscoveryCancelledEvent event)? onCancelled;

  final Future<void> Function(DiscoveryErrorEvent event)? onError;
}

/// Drives a discovery event stream against a caller-supplied persist callback.
///
/// This is the window-1 persistence core shared by
/// [DiscoveryPersistenceOrchestrator] and the synchronization coordinator:
///
/// ```text
/// DiscoveryEngine
///   → EventChannel batches
///     → persistBatch (transactional Drift upsert)
///       → observer.onBatchPersisted
///         → ACK current batch
/// ```
///
/// Contract: a batch is acknowledged **only** after its persistence committed.
/// On persistence failure, a rejected ACK, or a failing observer hook, the
/// batch is never acknowledged and the run fails loudly. Cancellation is
/// honored by stopping after the current batch's transaction finishes.
class DiscoveryStreamConsumer {
  const DiscoveryStreamConsumer({required this.persistBatch, this.observer});

  final Future<int> Function(DiscoveryBatchEvent event) persistBatch;
  final DiscoveryStreamObserver? observer;

  /// Drives [events] to persistence, acknowledging each batch through
  /// [ackBatch]. Returns after a terminal event (`discoveryCompleted`,
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
    ) async => DiscoveryRunSummary(
      state: DiscoveryLifecycleState.failed,
      batchesPersisted: batchesPersisted,
      recordsPersisted: recordsPersisted,
      errorCode: code,
      errorMessage: message,
      failedBatchSequence: sequence,
    );

    Future<void> runHook(Future<void>? pending) async {
      if (pending != null) await pending;
    }

    try {
      await for (final event in events) {
        switch (event) {
          case DiscoveryBatchEvent():
            try {
              final written = await persistBatch(event);
              try {
                await runHook(observer?.onBatchPersisted?.call(event, written));
              } catch (error) {
                return await failCore(
                  'persistenceFailed',
                  'An observer rejected the batch before it was acknowledged'
                      ' (${error.runtimeType}).',
                  event.sequence,
                );
              }
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
          case DiscoveryStartedEvent():
            final startedError = await _guard(
              () => runHook(observer?.onStarted?.call(event)),
            );
            if (startedError != null) {
              return await failCore(
                'persistenceFailed',
                'An observer rejected the start of a scan'
                    ' (${startedError.runtimeType}).',
                null,
              );
            }
          case DiscoveryProgressEvent():
            final progressError = await _guard(
              () => runHook(observer?.onProgress?.call(event)),
            );
            if (progressError != null) {
              return await failCore(
                'persistenceFailed',
                'An observer rejected a progress event'
                    ' (${progressError.runtimeType}).',
                null,
              );
            }
          case DiscoveryCompletedEvent():
            final completedError = await _guard(
              () => runHook(observer?.onCompleted?.call(event)),
            );
            if (completedError != null) {
              return await failCore(
                'persistenceFailed',
                'An observer rejected completion (${completedError.runtimeType}).',
                null,
              );
            }
            return DiscoveryRunSummary(
              state: DiscoveryLifecycleState.completed,
              batchesPersisted: batchesPersisted,
              recordsPersisted: recordsPersisted,
            );
          case DiscoveryCancelledEvent():
            final cancelledError = await _guard(
              () => runHook(observer?.onCancelled?.call(event)),
            );
            if (cancelledError != null) {
              return await failCore(
                'persistenceFailed',
                'An observer rejected cancellation'
                    ' (${cancelledError.runtimeType}).',
                null,
              );
            }
            return DiscoveryRunSummary(
              state: DiscoveryLifecycleState.cancelled,
              batchesPersisted: batchesPersisted,
              recordsPersisted: recordsPersisted,
            );
          case DiscoveryErrorEvent():
            final errorError = await _guard(
              () => runHook(observer?.onError?.call(event)),
            );
            if (errorError != null) {
              return await failCore(
                'persistenceFailed',
                'An observer rejected the error event'
                    ' (${errorError.runtimeType}).',
                null,
              );
            }
            return DiscoveryRunSummary(
              state: DiscoveryLifecycleState.failed,
              batchesPersisted: batchesPersisted,
              recordsPersisted: recordsPersisted,
              errorCode: event.code,
              errorMessage: event.message,
            );
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

  /// Runs [action] returning any thrown error, or null on success.
  Future<Object?> _guard(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (error) {
      return error;
    }
  }
}

/// Consumes the standalone scanner's bounded batches and persists them before
/// acknowledging — the same contract as [DiscoveryStreamConsumer], wired to a
/// [MediaRepository].
class DiscoveryPersistenceOrchestrator {
  const DiscoveryPersistenceOrchestrator({
    required this.repository,
    this.observer,
  });

  final MediaRepository repository;
  final DiscoveryStreamObserver? observer;

  /// Drives [events] (the `MediaDiscovery.events()` stream) against the
  /// repository, acknowledging each batch through [ackBatch] (normally
  /// `MediaDiscovery.ackBatch`).
  Future<DiscoveryRunSummary> run({
    required Stream<DiscoveryEvent> events,
    required Future<bool> Function(int sequence) ackBatch,
  }) {
    return DiscoveryStreamConsumer(
      persistBatch: (event) => repository.upsertBatch(
        event.records,
        generationAfter: event.generationAfter,
        accessScope: event.accessScope,
      ),
      observer: observer,
    ).run(events: events, ackBatch: ackBatch);
  }
}
