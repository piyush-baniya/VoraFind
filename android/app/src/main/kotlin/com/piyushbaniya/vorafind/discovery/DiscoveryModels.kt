package com.piyushbaniya.vorafind.discovery

import com.piyushbaniya.vorafind.content.ContentCategory

/** Wire contract version, mirrors the Dart facade constant. */
const val DISCOVERY_CONTRACT_VERSION: Int = 1

/** Scanner lifecycle state (subset of the architecture §14 state machine). */
enum class DiscoveryState(val wire: String) {
    IDLE("idle"),
    RUNNING("running"),
    COMPLETED("completed"),
    CANCELLED("cancelled"),
    FAILED("failed");

    companion object {
        fun fromWire(value: String): DiscoveryState =
            entries.firstOrNull { it.wire == value }
                ?: throw IllegalArgumentException("Unknown discovery state: $value")
    }
}

/** Access scope the platform reports for a scanned category. */
enum class AccessScope(val wire: String) {
    FULL("full"),
    PARTIAL("partial");

    companion object {
        fun fromState(state: com.piyushbaniya.vorafind.content.ContentAccessState): AccessScope =
            when (state) {
                com.piyushbaniya.vorafind.content.ContentAccessState.PARTIAL_ACCESS -> PARTIAL
                else -> FULL
            }
    }
}

/** Per-category outcome surfaced to the caller right after `startDiscovery`. */
enum class CategoryStartStatus(val wire: String) {
    STARTED("started"),
    PARTIAL("partial"),
    UNAVAILABLE("unavailable");

    companion object {
        fun fromWire(value: String): CategoryStartStatus =
            entries.firstOrNull { it.wire == value }
                ?: throw IllegalArgumentException("Unknown category status: $value")
    }
}

data class StartCategoryStatus(
    val category: ContentCategory,
    val status: CategoryStartStatus,
    val accessScope: AccessScope?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "category" to category.wire,
        "status" to status.wire,
        "accessScope" to accessScope?.wire,
    )
}

/** Result of `startDiscovery`. `accepted == false` carries a user-safe [code]. */
data class DiscoveryStartResult(
    val accepted: Boolean,
    val contractVersion: Int,
    val code: String?,
    val categories: List<StartCategoryStatus>,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "accepted" to accepted,
        "contractVersion" to contractVersion,
        "code" to code,
        "categories" to categories.map { it.toMap() },
    )
}

/** Lowest-level block the engine scans: one category on one volume. */
data class DiscoveryPlan(
    val category: ContentCategory,
    val volumeName: String,
    val accessScope: AccessScope,
)

/** Point-in-time snapshot for `getDiscoveryStatus`. */
data class DiscoveryStatus(
    val state: DiscoveryState,
    val currentCategory: String?,
    val currentVolume: String?,
    val sequence: Int,
    val batchesSent: Int,
    val recordsDiscovered: Long,
    val skippedRecords: Long,
    val lastError: String?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "state" to state.wire,
        "currentCategory" to currentCategory,
        "currentVolume" to currentVolume,
        "sequence" to sequence,
        "batchesSent" to batchesSent,
        "recordsDiscovered" to recordsDiscovered,
        "skippedRecords" to skippedRecords,
        "lastError" to lastError,
    )
}

/** One bounded page of records returned by a [DiscoveryQuerier]. */
data class QueryPage(
    val records: List<MediaDiscoveryRecord>,
    val hasMore: Boolean,
    val generationAfter: Long?,
    val skippedCount: Int,
    /** _ID of the last row consumed inside this page's batch window, even if it
     *  failed mapping — lets a fully-skipped page still advance the keyset. */
    val lastBatchId: Long?,
)

/** A single paged request for the native querier. */
data class QueryRequest(
    val category: ContentCategory,
    val volumeName: String,
    val lastId: Long,
    val batchSize: Int,
    val isCancelled: () -> Boolean,
)