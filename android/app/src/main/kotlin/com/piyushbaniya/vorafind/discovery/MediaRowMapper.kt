package com.piyushbaniya.vorafind.discovery

import android.provider.MediaStore
import com.piyushbaniya.vorafind.content.ContentCategory

/** Raised when a row cannot be mapped (e.g. missing `_ID`). The row is skipped. */
class RowMappingException(message: String) : Exception(message)

/**
 * Pure conversion of one [MediaStoreRow] into a [MediaDiscoveryRecord].
 *
 * Fault tolerant: malformed column values degrade to null; only the absence of
 * the identity column `_ID` is fatal for a row. No Android calls — JVM-testable.
 *
 * Column constants compile to plain strings so referencing API-29+ columns is
 * safe here; whether an old provider actually serves the column is decided by
 * [MediaStoreRow] column-existence checks.
 */
object MediaRowMapper {

    fun map(row: MediaStoreRow, category: ContentCategory, volumeName: String): MediaDiscoveryRecord {
        val id = row.longOrNull(MediaStore.MediaColumns._ID)
            ?: throw RowMappingException("row is missing _ID")
        val displayName = row.stringOrNull(MediaStore.MediaColumns.DISPLAY_NAME).orEmpty()
        val relativePath = row.stringOrNull(MediaStore.MediaColumns.RELATIVE_PATH)
        val bucket = row.stringOrNull(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
        val sizeBytes = row.longOrNull(MediaStore.MediaColumns.SIZE)
        val dateAdded = row.longOrNull(MediaStore.MediaColumns.DATE_ADDED)
        val dateModified = row.longOrNull(MediaStore.MediaColumns.DATE_MODIFIED)
        val width = row.longOrNull(MediaStore.MediaColumns.WIDTH)?.toInt()
        val height = row.longOrNull(MediaStore.MediaColumns.HEIGHT)?.toInt()
        val durationMs = row.longOrNull(MediaStore.MediaColumns.DURATION)

        val isImage = category == ContentCategory.IMAGES
        val screenshot = if (isImage) {
            ScreenshotClassifier.classify(
                relativePath = relativePath,
                bucketDisplayName = bucket,
                displayName = displayName,
                mimeType = row.stringOrNull(MediaStore.MediaColumns.MIME_TYPE),
                sizeBytes = sizeBytes,
            )
        } else {
            null
        }

        return MediaDiscoveryRecord(
            category = category,
            volumeName = volumeName,
            mediaStoreId = id,
            stableKey = MediaDiscoveryRecord.stableKey(volumeName, id),
            relinkSignature = RelinkSignature.compute(
                relativePath = relativePath,
                displayName = displayName,
                sizeBytes = sizeBytes,
                dateModified = dateModified,
            ),
            contentUri = row.contentUri(),
            displayName = displayName,
            mimeType = row.stringOrNull(MediaStore.MediaColumns.MIME_TYPE),
            sizeBytes = sizeBytes,
            dateAdded = dateAdded,
            dateModified = dateModified,
            relativePath = relativePath,
            bucketDisplayName = bucket,
            width = if (isImage || category == ContentCategory.VIDEOS) width else null,
            height = if (isImage || category == ContentCategory.VIDEOS) height else null,
            durationMs = if (isImage) null else durationMs,
            title = if (category == ContentCategory.AUDIO) {
                row.stringOrNull(MediaStore.Audio.AudioColumns.TITLE)
            } else {
                null
            },
            artist = if (category == ContentCategory.AUDIO) {
                row.stringOrNull(MediaStore.Audio.AudioColumns.ARTIST)
            } else {
                null
            },
            album = if (category == ContentCategory.AUDIO) {
                row.stringOrNull(MediaStore.Audio.AudioColumns.ALBUM)
            } else {
                null
            },
            screenshotScore = screenshot?.score,
            isScreenshot = screenshot?.isScreenshot,
        )
    }
}