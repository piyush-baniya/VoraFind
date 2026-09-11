package com.piyushbaniya.vorafind.discovery

import com.piyushbaniya.vorafind.content.ContentAccessState
import com.piyushbaniya.vorafind.content.ContentCategory
import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Scanner-level failure inside one collection; terminates the session with `discoveryError`. */
class DiscoveryFailure(message: String) : Exception(message)

/**
 * Runs a full discovery session on a single daemon thread with window-1 (ACK)
 * backpressure: a `discoveryBatch` event is only followed by the next page after
 * the Dart side explicitly acks that batch (architecture §11).
 *
 * Invariants:
 *  - events are sent only from the engine thread (single writer);
 *  - `ackBatch`/`cancel`/`status` are safe from any thread;
 *  - cancellation checks happen per row and are never swallowed;
 *  - a failed or cancelled session never resumes automatically.
 */
class DiscoveryEngine(
    private val querier: DiscoveryQuerier,
    private val accessFor: (ContentCategory) -> ContentAccessState,
    private val batchSize: Int = DEFAULT_BATCH_SIZE,
) {

    @Volatile private var sink: DiscoveryEventSink = NoopDiscoveryEventSink
    private val stateRef = AtomicReference(DiscoveryState.IDLE)
    private val cancelled = AtomicBoolean(false)

    @Volatile private var sequence = 0
    @Volatile private var batchesSent = 0
    @Volatile private var recordsDiscovered = 0L
    @Volatile private var skippedRecords = 0L
    @Volatile private var currentCategory: ContentCategory? = null
    @Volatile private var currentVolume: String? = null
    @Volatile private var lastError: String? = null

    private val lock = Any()
    private var pendingAckSeq: Int? = null
    private var pendingAckFuture: CompletableFuture<Void>? = null

    private val executor: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "vorafind-discovery").apply { isDaemon = true }
    }

    fun attachSink(sink: DiscoveryEventSink?) {
        this.sink = sink ?: NoopDiscoveryEventSink
    }

    /**
     * Validates capability and listener availability synchronously; the session
     * itself runs on the engine thread. Always returns a value-bearing result
     * (no exceptions for normal outcomes).
     */
    fun start(options: DiscoveryOptions): DiscoveryStartResult {
        val statuses = mutableListOf<StartCategoryStatus>()
        val plans = mutableListOf<DiscoveryPlan>()
        val desiredVolumes = options.volumes
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?.toSet()
            ?.takeIf { it.isNotEmpty() }
        // Intersect the caller's volume filter with the volumes the querier
        // actually reports; a volume that vanished is simply not planned.
        val scanVolumes = querier.volumes().filter { desiredVolumes == null || it in desiredVolumes }
        for (category in options.categories) {
            val status = startCategoryStatus(category)
            statuses += status
            if (status.status != CategoryStartStatus.UNAVAILABLE) {
                for (volume in scanVolumes) {
                    plans += DiscoveryPlan(
                        category = category,
                        volumeName = volume,
                        accessScope = status.accessScope ?: AccessScope.FULL,
                    )
                }
            }
        }
        synchronized(lock) {
            // Only a live session blocks the next one; terminal states
            // (completed/cancelled/failed) may be reused by a later start.
            if (stateRef.get() == DiscoveryState.RUNNING) {
                return DiscoveryStartResult(false, DISCOVERY_CONTRACT_VERSION, "busy", emptyList())
            }
            if (sink === NoopDiscoveryEventSink) {
                return DiscoveryStartResult(false, DISCOVERY_CONTRACT_VERSION, "eventListenerNotAttached", emptyList())
            }
            if (plans.isEmpty() && statuses.isEmpty()) {
                return DiscoveryStartResult(false, DISCOVERY_CONTRACT_VERSION, "invalidArguments", emptyList())
            }
            sequence = 0
            batchesSent = 0
            recordsDiscovered = 0L
            skippedRecords = 0L
            lastError = null
            cancelled.set(false)
            stateRef.set(DiscoveryState.RUNNING)
        }
        executor.execute { runSession(plans, statuses) }
        return DiscoveryStartResult(true, DISCOVERY_CONTRACT_VERSION, null, statuses)
    }

    /** MediaStore generation snapshot for the "unchanged" fast-check (§15). */
    fun probeGeneration(category: ContentCategory, volumeName: String): Long? =
        querier.probeGeneration(category, volumeName)

    private fun startCategoryStatus(category: ContentCategory): StartCategoryStatus {
        if (category == ContentCategory.DOCUMENTS) {
            return StartCategoryStatus(category, CategoryStartStatus.UNAVAILABLE, null)
        }
        val access = try {
            accessFor(category)
        } catch (_: Exception) {
            return StartCategoryStatus(category, CategoryStartStatus.UNAVAILABLE, null)
        }
        return when (access) {
            ContentAccessState.FULL_ACCESS ->
                StartCategoryStatus(category, CategoryStartStatus.STARTED, AccessScope.FULL)
            ContentAccessState.PARTIAL_ACCESS ->
                StartCategoryStatus(category, CategoryStartStatus.PARTIAL, AccessScope.PARTIAL)
            else ->
                StartCategoryStatus(category, CategoryStartStatus.UNAVAILABLE, null)
        }
    }

    private fun runSession(plans: List<DiscoveryPlan>, statuses: List<StartCategoryStatus>) {
        var failed: String? = null
        var errorCode = "scannerFailed"
        try {
            for (plan in plans) {
                if (cancelled.get()) break
                currentCategory = plan.category
                currentVolume = plan.volumeName
                emitStarted(plan)
                runCollection(plan)
            }
        } catch (e: CancellationException) {
            cancelled.set(true)
        } catch (e: DiscoveryFailure) {
            failed = e.message
            errorCode = "scannerFailed"
        } catch (e: Exception) {
            failed = e.message ?: e.javaClass.simpleName
            errorCode = "scannerFailed"
        } finally {
            currentCategory = null
            currentVolume = null
        }
        when {
            failed != null -> {
                lastError = failed
                stateRef.set(DiscoveryState.FAILED)
                sink.send(discoveryEvent("discoveryError") {
                    put("code", errorCode)
                    put("message", failed)
                })
            }
            cancelled.get() -> {
                lastError = null
                stateRef.set(DiscoveryState.CANCELLED)
                sink.send(discoveryEvent("discoveryCancelled") {
                    put("recordsDiscovered", recordsDiscovered)
                    put("skippedRecords", skippedRecords)
                    put("batchesSent", batchesSent)
                })
            }
            else -> {
                stateRef.set(DiscoveryState.COMPLETED)
                sink.send(discoveryEvent("discoveryCompleted") {
                    put("recordsDiscovered", recordsDiscovered)
                    put("skippedRecords", skippedRecords)
                    put("batchesSent", batchesSent)
                    put("categories", statuses.filter { it.status != CategoryStartStatus.UNAVAILABLE }.map { it.category.wire })
                    put("volumes", plans.map { it.volumeName }.distinct())
                })
            }
        }
    }

    private fun runCollection(plan: DiscoveryPlan) {
        var lastId = 0L
        while (true) {
            if (cancelled.get()) break
            val page = querier.queryPage(
                QueryRequest(
                    category = plan.category,
                    volumeName = plan.volumeName,
                    lastId = lastId,
                    batchSize = batchSize,
                    isCancelled = { cancelled.get() },
                )
            )
            skippedRecords += page.skippedCount
            if (page.hasMore && page.lastBatchId == null && page.records.isEmpty()) {
                throw DiscoveryFailure("Provider returned rows without identity; cannot advance cursor")
            }
            if (page.records.isEmpty()) {
                if (!page.hasMore) break
                lastId = page.lastBatchId ?: throw DiscoveryFailure("Provider returned no records to advance cursor")
                continue
            }
            lastId = page.lastBatchId ?: page.records.last().mediaStoreId
            val batchSequence = nextSequence()
            val waitsForAck = page.hasMore
            synchronized(lock) {
                pendingAckSeq = batchSequence
                pendingAckFuture = if (waitsForAck) {
                    CompletableFuture<Void>()
                } else {
                    null
                }
            }
            sink.send(
                discoveryEvent("discoveryBatch") {
                    put("sequence", batchSequence)
                    put("category", plan.category.wire)
                    put("volume", plan.volumeName)
                    put("accessScope", plan.accessScope.wire)
                    put("records", page.records.map { it.toMap() })
                    put("hasMore", page.hasMore)
                    put("skippedCount", page.skippedCount)
                    put("generationAfter", page.generationAfter)
                }
            )
            recordsDiscovered += page.records.size
            batchesSent += 1
            sink.send(
                discoveryEvent("discoveryProgress") {
                    put("sequence", batchSequence)
                    put("category", plan.category.wire)
                    put("volume", plan.volumeName)
                    put("accessScope", plan.accessScope.wire)
                    put("recordsDiscovered", recordsDiscovered)
                    put("skippedRecords", skippedRecords)
                    put("batchesSent", batchesSent)
                    put("batchesRemaining", if (page.hasMore) 1 else 0)
                }
            )
            // The ack gates the NEXT page only; a terminal batch (hasMore == false)
            // must never strand the session waiting for an ack that no page depends on.
            if (waitsForAck) {
                val acked = awaitAck(batchSequence)
                if (!acked) break
            }
            if (cancelled.get() || !page.hasMore) break
        }
    }

    /** Blocks until Dart acks this batch sequence or the session is cancelled. */
    private fun awaitAck(sequence: Int): Boolean {
        val future = synchronized(lock) {
            if (stateRef.get() != DiscoveryState.RUNNING) return false
            pendingAckFuture
        } ?: return false
        return try {
            future.get()
            true
        } catch (e: CancellationException) {
            false
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
    }

    /** Acks the batch [sequence]; false for unknown, duplicate, or stale acks.
     *  Terminal batches need no ack, but acking them still returns true (no-op). */
    fun ackBatch(sequence: Int): Boolean = synchronized(lock) {
        if (stateRef.get() != DiscoveryState.RUNNING || pendingAckSeq != sequence) {
            return@synchronized false
        }
        val future = pendingAckFuture
        when {
            future == null -> true // terminal batch: nothing to release
            !future.isDone -> {
                future.complete(null)
                true
            }
            else -> false // duplicate ack of a gating batch
        }
    }

    /**
     * Requests cancellation: safe at every lifecycle stage, idempotent, and never
     * throws. Waits for the engine thread to settle before returning.
     */
    fun cancel(): Boolean {
        synchronized(lock) {
            if (stateRef.get() != DiscoveryState.RUNNING) return false
            cancelled.set(true)
            pendingAckFuture?.let { future ->
                if (!future.isDone) future.completeExceptionally(CancellationException("Discovery cancelled"))
            }
        }
        return true
    }

    fun status(): DiscoveryStatus = synchronized(lock) {
        DiscoveryStatus(
            state = stateRef.get(),
            currentCategory = currentCategory?.wire,
            currentVolume = currentVolume,
            sequence = sequence,
            batchesSent = batchesSent,
            recordsDiscovered = recordsDiscovered,
            skippedRecords = skippedRecords,
            lastError = lastError,
        )
    }

    private fun nextSequence(): Int = (sequence + 1).also { sequence = it }

    private fun emitStarted(plan: DiscoveryPlan) {
        sink.send(
            discoveryEvent("discoveryStarted") {
                put("category", plan.category.wire)
                put("volume", plan.volumeName)
                put("accessScope", plan.accessScope.wire)
            }
        )
    }

    private inline fun discoveryEvent(type: String, crossinline block: MutableMap<String, Any?>.() -> Unit): Map<String, Any?> =
        mutableMapOf<String, Any?>("type" to type).apply(block)

    private companion object {
        const val DEFAULT_BATCH_SIZE = 500
    }
}

/** Caller-supplied discovery options. */
data class DiscoveryOptions(
    val categories: List<ContentCategory>,
    /** Absolute volume names to scan; null or empty scans every available volume. */
    val volumes: List<String>? = null,
)