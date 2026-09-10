package com.piyushbaniya.vorafind.discovery

/**
 * Data-driven screenshot heuristic (architecture §17).
 *
 * Derived metadata, never authoritative. Signals contribute weighted scores; a
 * score at/above [THRESHOLD] classifies the record as a likely screenshot. All
 * signals are evaluated from MediaStore metadata only (path/bucket, filename,
 * MIME type, size) — no decoding, no OCR, no filesystem access.
 */
object ScreenshotClassifier {

    /** A single strong signal is sufficient (scores are weighted sums). */
    const val THRESHOLD: Int = 60
    const val MAX_SCORE: Int = 100

    /** Strong: RELATIVE_PATH / BUCKET_DISPLAY_NAME mentions screenshots. */
    private const val PATH_WEIGHT: Int = 60

    /** Strong: AOSP ImageExporter filename `Screenshot_yyyyMMdd-HHmmss(.ext)`. */
    private const val AOSP_FILENAME_WEIGHT: Int = 60

    /** Medium: known OEM prefixes. */
    private const val OEM_PREFIX_WEIGHT: Int = 35

    /** Low: plausible picture type and size for a snapshot. */
    private const val SNAPSHOT_WEIGHT: Int = 10

    private val aospFilenamePattern =
        Regex("^Screenshot_\\d{8}-\\d{6}(\\.[A-Za-z0-9]+)?$")

    private val oemPrefixes = listOf(
        "screenshot_",
        "screenshot-",
        "screencapture",
        "skcapture",
    )

    private val snapshotMimeTypes = setOf("image/png", "image/jpeg", "image/webp")
    private const val MIN_SNAPSHOT_BYTES = 50_000L
    private const val MAX_SNAPSHOT_BYTES = 25_000_000L

    data class Result(val score: Int, val isScreenshot: Boolean)

    /** Pure: evaluates only the metadata it receives. */
    fun classify(
        relativePath: String?,
        bucketDisplayName: String?,
        displayName: String?,
        mimeType: String?,
        sizeBytes: Long?,
    ): Result {
        var score = 0
        val path = relativePath.orEmpty().lowercase()
        val bucket = bucketDisplayName.orEmpty().lowercase()
        if (path.contains("screenshot") || bucket.contains("screenshot")) {
            score += PATH_WEIGHT
        }
        if (displayName?.matches(aospFilenamePattern) == true) {
            score += AOSP_FILENAME_WEIGHT
        }
        if (hasOemPrefix(displayName)) {
            score += OEM_PREFIX_WEIGHT
        }
        if (mimeType in snapshotMimeTypes &&
            sizeBytes != null &&
            sizeBytes in MIN_SNAPSHOT_BYTES..MAX_SNAPSHOT_BYTES
        ) {
            score += SNAPSHOT_WEIGHT
        }
        val capped = score.coerceAtMost(MAX_SCORE)
        return Result(score = capped, isScreenshot = capped >= THRESHOLD)
    }

    private fun hasOemPrefix(displayName: String?): Boolean {
        val name = displayName?.lowercase() ?: return false
        return oemPrefixes.any { name.startsWith(it) }
    }
}