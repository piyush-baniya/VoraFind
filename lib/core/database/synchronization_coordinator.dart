import 'dart:async';

import '../platform/content_access.dart';
import '../platform/content_access_models.dart';
import '../platform/media_discovery.dart';
import '../platform/media_discovery_models.dart';
import 'deletion_reconciler.dart';
import 'discovery_persistence_orchestrator.dart';
import 'media_repository.dart';

/// How one (category, volume) synchronization unit ended.
///
/// * `firstIndex` — a full-scope scan created the first checkpoint.
/// * `unchanged` — generation fast-check matched; nothing needed scanning.
/// * `reconciled` — a full-scope rescan reconciled against an existing
///   checkpoint (adds, updates, and safe deletions).
/// * `partialAccess` — a partial-scope rescan that adds/updates only.
/// * `unavailable` — the category could not be accessed, or the volume
///   vanished between planning and scanning.
/// * `cancelled` — the session was cancelled before this unit concluded.
/// * `failed` — this unit's scan or persistence failed.
enum SyncUnitKind {
  firstIndex,
  unchanged,
  reconciled,
  partialAccess,
  unavailable,
  cancelled,
  failed,
}

/// Overall outcome of one synchronization run.
enum SyncSessionOutcome {
  completed,
  partialFailure,
  cancelled,
  failed,
  noAccess,
}

/// Outcome for one (category, volume) synchronization unit.
class SyncUnitResult {
  const SyncUnitResult({
    required this.category,
    required this.volumeName,
    required this.kind,
    this.recordsInserted = 0,
    this.recordsUpdated = 0,
    this.recordsUnchanged = 0,
    this.recordsDeleted = 0,
    this.checkpointAdvanced = false,
    this.errorCode,
    this.errorMessage,
  });

  final ContentCategory category;
  final String volumeName;
  final SyncUnitKind kind;
  final int recordsInserted;
  final int recordsUpdated;
  final int recordsUnchanged;
  final int recordsDeleted;

  /// True when a durable sync checkpoint was saved for this unit.
  final bool checkpointAdvanced;

  final String? errorCode;
  final String? errorMessage;
}

/// Result of one synchronization run, in deterministic category × volume order.
class SyncSessionResult {
  const SyncSessionResult({required this.outcome, required this.units});

  final SyncSessionOutcome outcome;
  final List<SyncUnitResult> units;
}

typedef _UnitKey = ({ContentCategory category, String volume});

/// Coordinate-keyed runtime state for one planned unit.
class _UnitPlan {
  _UnitPlan({
    required this.category,
    required this.volumeName,
    required this.available,
    this.scope,
    required this.hadCheckpoint,
  });

  final ContentCategory category;
  final String volumeName;

  /// False when the category cannot be queried at all (or the volume filter
  /// dropped it); such units never scan.
  final bool available;

  /// Scope seen by the scanner; non-null only when [available].
  final DiscoveryAccessScope? scope;

  final bool hadCheckpoint;

  // --- mutable runtime state, updated while the session runs ---
  bool finalized = false;
  bool unitReachedEnd = false;
  int recordsInserted = 0;
  int recordsUpdated = 0;
  int recordsUnchanged = 0;
  int recordsDeleted = 0;
  int? lastGenerationAfter;
  SyncUnitKind? kind;
  bool checkpointAdvanced = false;
  String? errorCode;
  String? errorMessage;
}

/// Runs incremental MediaStore synchronization against the indexed library
/// (architecture §15).
///
/// ## What a run does per (category, volume)
///
/// 1. **Fast path.** When a durable checkpoint exists, its access scope was
///    full, it carries a MediaStore generation, and the current generation
///    still equals it, the unit is reported as `unchanged` and not scanned.
/// 2. **Scan.** Otherwise the unit is scanned. Full-scope units additionally
///    run deletion reconciliation against the persisted index; partial-scope
///    units only add/update. Checkpoints are saved only for units that
///    concluded cleanly under full scope (writing a partial checkpoint would
///    silently discard the last good full snapshot).
/// 3. **Finalize.** A unit is finalized cleanly when its own scan ran to the
///    end (its final batch reported `hasMore == false`) or a terminal session
///    event confirms completion; everything else is `cancelled`/`failed` and
///    carries no checkpoint.
///
/// Generation is a change *detector*, never a changed-record cursor: an
/// unmatched generation simply forces a full bounded scan of that unit.
class SynchronizationCoordinator {
  SynchronizationCoordinator({
    required this.repository,
    required this.discovery,
    required this.contentAccess,
    this.nowSeconds,
    this.reconciliationPageSize = 500,
    this.deletionChunkSize = 500,
  });

  static const fallbackVolume = 'external_primary';

  final MediaRepository repository;
  final MediaDiscovery discovery;
  final ContentAccess contentAccess;

  /// Injectable clock for deterministic tests (epoch seconds).
  final int Function()? nowSeconds;

  final int reconciliationPageSize;
  final int deletionChunkSize;

  late final DeletionReconciler _reconciler;
  _UnitPlan? _active;
  late List<_UnitPlan> _plans;

  /// Synchronizes [categories] across every external MediaStore volume.
  ///
  /// The engine is driven with one session per category and only the volumes
  /// that actually need scanning, so a unit whose generation fast-check passed
  /// is never rescanned. Each session attaches to `discovery.events()` before
  /// `startDiscovery` (the native engine refuses a start without an attached
  /// listener) and buffers events until the consumer picks them up.
  Future<SyncSessionResult> run(List<ContentCategory> categories) async {
    final requested = List<ContentCategory>.of(categories);
    if (requested.isEmpty) {
      return const SyncSessionResult(
        outcome: SyncSessionOutcome.completed,
        units: [],
      );
    }

    final capabilities = await contentAccess.getCapabilities();
    final volumes = capabilities.externalVolumes.isEmpty
        ? const [fallbackVolume]
        : capabilities.externalVolumes.toList(growable: false);

    _reconciler = DeletionReconciler(
      fetchPage: (category, volumeName, afterId, limit) =>
          repository.fetchIndexedPage(
            category: category,
            volumeName: volumeName,
            afterId: afterId,
            limit: limit,
          ),
      deleteKeys: repository.deleteByStableKeys,
      pageSize: reconciliationPageSize,
      chunkSize: deletionChunkSize,
    );

    // Plan units in stable order: requested categories × volume order.
    _plans = [];
    final byKey = <_UnitKey, _UnitPlan>{};
    for (final category in requested) {
      final access = capabilities.accessFor(category);
      final available = access.canReadSelected;
      final scope = available
          ? (access.canReadAll
                ? DiscoveryAccessScope.full
                : DiscoveryAccessScope.partial)
          : null;
      for (final volume in volumes) {
        final hadCheckpoint =
            available && (await _readCheckpoint(category, volume) != null);
        final plan = _UnitPlan(
          category: category,
          volumeName: volume,
          available: available,
          scope: scope,
          hadCheckpoint: hadCheckpoint,
        );
        if (!available) {
          plan.kind = SyncUnitKind.unavailable;
          plan.finalized = true;
        }
        _plans.add(plan);
        byKey[_key(plan.category, plan.volumeName)] = plan;
      }
    }

    final toScan = _plans.where((plan) => plan.available).toList();
    if (toScan.isEmpty) {
      return _finish(SyncSessionOutcome.noAccess);
    }

    // Fast path: skip units whose full-scope generation matched. A unit's scan
    // flag stays false so its category session never includes its volume.
    for (final plan in toScan) {
      final checkpoint = await _readCheckpoint(plan.category, plan.volumeName);
      final probe = await _probeGeneration(plan.category, plan.volumeName);
      if (_isUnchanged(plan, checkpoint, probe)) {
        plan.kind = SyncUnitKind.unchanged;
        plan.checkpointAdvanced = true;
        plan.lastGenerationAfter = probe;
        plan.finalized = true;
        await _saveCheckpoint(plan, probe, SyncUnitKind.unchanged);
      }
    }

    final scanByCategory = <ContentCategory, List<_UnitPlan>>{};
    for (final plan in toScan) {
      if (plan.finalized) continue;
      scanByCategory.putIfAbsent(plan.category, () => []).add(plan);
    }

    if (scanByCategory.isEmpty) {
      return _finish(SyncSessionOutcome.completed);
    }

    var sessionCancelled = false;
    var sessionFailed = false;
    for (final entry in scanByCategory.entries) {
      final category = entry.key;
      final scanUnits = entry.value;
      final volumeFilter = [for (final plan in scanUnits) plan.volumeName];

      final controller = StreamController<DiscoveryEvent>();
      final subscription = discovery.events().listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      var consumed = false;

      try {
        DiscoveryStartResult start;
        try {
          start = await discovery.startDiscovery([
            category,
          ], volumes: volumeFilter);
        } catch (_) {
          start = DiscoveryStartResult(
            accepted: false,
            contractVersion: 1,
            code: 'discoveryStartFailed',
            categories: const [],
          );
        }
        if (!start.accepted) {
          _failScanUnits(scanUnits, start.code ?? 'discoveryStartFailed');
          sessionFailed = true;
          continue;
        }

        consumed = true;
        final consumer = _buildConsumer(byKey);
        final summary = await consumer.run(
          events: controller.stream,
          ackBatch: discovery.ackBatch,
        );

        // Unblock the window-1 engine if the run ended before terminal events
        // (e.g. a batch that could not be persisted was never acknowledged).
        if (summary.state != DiscoveryLifecycleState.completed) {
          await discovery.cancelDiscovery();
        }
        if (summary.state == DiscoveryLifecycleState.cancelled) {
          sessionCancelled = true;
        } else if (summary.state == DiscoveryLifecycleState.failed) {
          sessionFailed = true;
        }
        _reconcileUnfinalized(scanUnits, summary);
      } finally {
        await subscription.cancel();
        if (consumed) {
          // The consumer (the controller's only listener) already detached;
          // closing now always completes.
          await controller.close();
        } else {
          // The session ended before the consumer attached (refused start):
          // a single-subscription controller with no listener never completes
          // close(), so release it without awaiting.
          unawaited(controller.close());
        }
      }
    }

    return _finish(_outcomeFor(sessionCancelled, sessionFailed));
  }

  DiscoveryStreamConsumer _buildConsumer(Map<_UnitKey, _UnitPlan> byKey) {
    return DiscoveryStreamConsumer(
      persistBatch: (event) async {
        final plan = byKey[_key(event.category, event.volume)];
        final delta = await repository.upsertBatchChanged(
          event.records,
          generationAfter: event.generationAfter,
          accessScope: event.accessScope,
        );
        if (plan != null) {
          plan.recordsInserted += delta.inserted;
          plan.recordsUpdated += delta.updated;
          plan.recordsUnchanged += delta.unchanged;
          plan.lastGenerationAfter =
              event.generationAfter ?? plan.lastGenerationAfter;
          if (!event.hasMore) plan.unitReachedEnd = true;
        }
        return delta.total;
      },
      observer: DiscoveryStreamObserver(
        onStarted: (event) async {
          await _finalizeActive(
            clean: true,
            onError: (plan) {
              plan.kind = SyncUnitKind.failed;
              plan.errorCode = 'inconsistentScan';
            },
          );
          final plan = byKey[_key(event.category, event.volume)];
          if (plan == null) return;
          _active = plan;
          if (plan.scope == DiscoveryAccessScope.full) {
            _reconciler.begin(plan.category, plan.volumeName);
          }
        },
        onBatchPersisted: (event, _) async {
          final plan = byKey[_key(event.category, event.volume)];
          if (plan == null || plan.scope != DiscoveryAccessScope.full) return;
          await _reconciler.observeMany(
            event.records.map((record) => record.mediaStoreId),
          );
        },
        onCompleted: (_) async {
          await _finalizeActive(clean: true);
        },
        onCancelled: (_) async {
          await _finalizeActive(
            clean: false,
            onError: (plan) {
              plan.kind = SyncUnitKind.cancelled;
            },
          );
        },
        onError: (event) async {
          await _finalizeActive(
            clean: false,
            onError: (plan) {
              plan.kind = SyncUnitKind.failed;
              plan.errorCode = event.code;
              plan.errorMessage = event.message;
            },
          );
        },
      ),
    );
  }

  /// Finalizes the currently active unit. Clean units (their scan ran to the
  /// end) may reconcile deletions and save a checkpoint; anything else is
  /// marked via [onError].
  Future<void> _finalizeActive({
    required bool clean,
    void Function(_UnitPlan plan)? onError,
  }) async {
    final plan = _active;
    if (plan == null) return;
    _active = null;
    if (plan.finalized) return;

    final concludedCleanly = clean || plan.unitReachedEnd;
    if (!concludedCleanly) {
      _reconciler.discard();
      plan.finalized = true;
      onError?.call(plan);
      return;
    }

    if (plan.scope == DiscoveryAccessScope.full) {
      try {
        plan.recordsDeleted = await _reconciler.apply();
      } catch (error) {
        _reconciler.discard();
        plan.finalized = true;
        plan.kind = SyncUnitKind.failed;
        plan.errorCode = 'deletionReconciliationFailed';
        plan.errorMessage =
            'Deletion reconciliation failed (${error.runtimeType}).';
        return;
      }
    } else {
      _reconciler.discard();
    }

    final kind = plan.scope == DiscoveryAccessScope.full
        ? (plan.hadCheckpoint
              ? SyncUnitKind.reconciled
              : SyncUnitKind.firstIndex)
        : SyncUnitKind.partialAccess;
    plan.kind = kind;
    final generation =
        plan.lastGenerationAfter ??
        await _probeGeneration(plan.category, plan.volumeName);
    try {
      await _saveCheckpoint(plan, generation, kind);
      plan.checkpointAdvanced = true;
    } catch (_) {
      plan.errorCode = 'persistenceFailed';
      plan.checkpointAdvanced = false;
    }
    plan.finalized = true;
  }

  /// Marks every unit a discovery session never started.
  void _reconcileUnfinalized(
    List<_UnitPlan> scanUnits,
    DiscoveryRunSummary summary,
  ) {
    final dropped = switch (summary.state) {
      DiscoveryLifecycleState.cancelled => SyncUnitKind.cancelled,
      _ =>
        summary.state == DiscoveryLifecycleState.failed
            ? SyncUnitKind.failed
            : SyncUnitKind.unavailable,
    };
    for (final plan in scanUnits) {
      if (plan.finalized) continue;
      plan.finalized = true;
      plan.kind = dropped;
      _reconciler.discard();
    }
  }

  SyncSessionResult _finish(SyncSessionOutcome outcome) {
    final units = _plans
        .where((plan) => plan.finalized)
        .map(
          (plan) => SyncUnitResult(
            category: plan.category,
            volumeName: plan.volumeName,
            kind: plan.kind ?? SyncUnitKind.unavailable,
            recordsInserted: plan.recordsInserted,
            recordsUpdated: plan.recordsUpdated,
            recordsUnchanged: plan.recordsUnchanged,
            recordsDeleted: plan.recordsDeleted,
            checkpointAdvanced: plan.checkpointAdvanced,
            errorCode: plan.errorCode,
            errorMessage: plan.errorMessage,
          ),
        )
        .toList(growable: false);
    return SyncSessionResult(outcome: outcome, units: units);
  }

  SyncSessionOutcome _outcomeFor(bool sessionCancelled, bool sessionFailed) {
    if (sessionCancelled) return SyncSessionOutcome.cancelled;
    if (sessionFailed) {
      return _plans.any(_succeeded)
          ? SyncSessionOutcome.partialFailure
          : SyncSessionOutcome.failed;
    }
    return SyncSessionOutcome.completed;
  }

  static bool _succeeded(_UnitPlan plan) =>
      plan.kind == SyncUnitKind.firstIndex ||
      plan.kind == SyncUnitKind.reconciled ||
      plan.kind == SyncUnitKind.partialAccess ||
      plan.kind == SyncUnitKind.unchanged;

  static bool _isUnchanged(
    _UnitPlan plan,
    SyncCheckpoint? checkpoint,
    int? probe,
  ) {
    if (checkpoint == null) return false;
    if (plan.scope != DiscoveryAccessScope.full) return false;
    if (checkpoint.lastAccessScope != DiscoveryAccessScope.full) return false;
    if (checkpoint.lastGeneration == null) return false;
    if (probe == null) return false;
    return checkpoint.lastGeneration == probe;
  }

  void _failScanUnits(List<_UnitPlan> scanUnits, String code) {
    for (final plan in scanUnits) {
      plan.finalized = true;
      plan.kind = SyncUnitKind.failed;
      plan.errorCode = code;
      plan.errorMessage = 'Discovery refused to start: $code';
    }
  }

  Future<int?> _probeGeneration(
    ContentCategory category,
    String volumeName,
  ) async {
    try {
      return await discovery.getGeneration(category, volumeName);
    } catch (_) {
      return null;
    }
  }

  Future<SyncCheckpoint?> _readCheckpoint(
    ContentCategory category,
    String volumeName,
  ) async {
    try {
      return await repository.getSyncCheckpoint(category, volumeName);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCheckpoint(
    _UnitPlan plan,
    int? generation,
    SyncUnitKind kind,
  ) {
    final scope = plan.scope ?? DiscoveryAccessScope.full;
    return repository.saveSyncCheckpoint(
      SyncCheckpoint(
        category: plan.category,
        volumeName: plan.volumeName,
        lastGeneration: generation,
        lastAccessScope: scope,
        lastSyncAt: (nowSeconds ?? _defaultNowSeconds)(),
        lastResult: kind.name,
      ),
    );
  }

  static _UnitKey _key(ContentCategory category, String volumeName) =>
      (category: category, volume: volumeName);

  static int _defaultNowSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
