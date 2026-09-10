package com.piyushbaniya.vorafind.discovery

import com.piyushbaniya.vorafind.content.ContentCategory

/**
 * One normalized MediaStore discovery record.
 *
 * Contains only discovery metadata (architecture §15.1 `indexed_items` subset):
 * never file bytes, thumbnails, OCR, or paths used as identity. Fields mirror the
 * canonical `content://` addressing needed by a future indexer.
 *
 * [stableKey] = `volumeName:mediaStoreId` per architecture §8.1. [relinkSignature]
 * is the re-link signature that survives MediaStore rebuilds (architecture §8.1).
 * [screenshotScore]/[isScreenshot] are derived, non-authoritative heuristic hints
 * (architecture §17), present only for image records.
 */
data class MediaDiscoveryRecord(
    val category: ContentCategory,
    val volumeName: String,
    val mediaStoreId: Long,
    val stableKey: String,
    val relinkSignature: String?,
    val contentUri: String,
    val displayName: String,
    val mimeType: String?,
    val sizeBytes: Long?,
    val dateAdded: Long?,
    val dateModified: Long?,
    val relativePath: String?,
    val bucketDisplayName: String?,
    val width: Int?,
    val height: Int?,
    val durationMs: Long?,
    val title: String?,
    val artist: String?,
    val album: String?,
    val screenshotScore: Int?,
    val isScreenshot: Boolean?,
) {
    /** Wire payload; keys are the Dart/Kotlin contract and must not drift. */
    fun toMap(): Map<String, Any?> = mapOf(
        "category" to category.wire,
        "volumeName" to volumeName,
        "mediaStoreId" to mediaStoreId,
        "stableKey" to stableKey,
        "relinkSignature" to relinkSignature,
        "contentUri" to contentUri,
        "displayName" to displayName,
        "mimeType" to mimeType,
        "sizeBytes" to sizeBytes,
        "dateAdded" to dateAdded,
        "dateModified" to dateModified,
        "relativePath" to relativePath,
        "bucketDisplayName" to bucketDisplayName,
        "width" to width,
        "height" to height,
        "durationMs" to durationMs,
        "title" to title,
        "artist" to artist,
        "album" to album,
        "screenshotScore" to screenshotScore,
        "isScreenshot" to isScreenshot,
    )

    companion object {
        /** Primary stable identity: `volumeName:mediaStoreId` (architecture §8.1). */
        fun stableKey(volumeName: String, mediaStoreId: Long): String =
            "$volumeName:$mediaStoreId"
    }
}