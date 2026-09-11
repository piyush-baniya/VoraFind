package com.piyushbaniya.vorafind.discovery

import android.provider.MediaStore
import com.piyushbaniya.vorafind.content.ContentCategory
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

/** In-memory [MediaStoreRow] for JVM tests. */
class FakeRow(
    private val longs: Map<String, Long?>,
    private val strings: Map<String, String?>,
    private val uri: String = "content://media/external/images/media/1",
) : MediaStoreRow {
    override fun longOrNull(column: String): Long? = longs[column]
    override fun stringOrNull(column: String): String? = strings[column]
    override fun contentUri(): String = uri
}

/** A typical image row with defaults; override to build edge cases. */
fun imageRow(
    id: Long,
    name: String = "photo.jpg",
    relativePath: String? = "DCIM/Camera/",
    mimeType: String? = "image/jpeg",
    sizeBytes: Long? = 1_000_000,
    width: Long? = 1920,
    height: Long? = 1080,
    bucket: String? = "Camera",
    uri: String = "content://media/external/images/media/$id",
): FakeRow = FakeRow(
    longs = mapOf(
        MediaStore.MediaColumns._ID to id,
        MediaStore.MediaColumns.SIZE to sizeBytes,
        MediaStore.MediaColumns.DATE_ADDED to 1_000L + id,
        MediaStore.MediaColumns.DATE_MODIFIED to 2_000L + id,
        MediaStore.MediaColumns.WIDTH to width,
        MediaStore.MediaColumns.HEIGHT to height,
    ),
    strings = mapOf(
        MediaStore.MediaColumns.DISPLAY_NAME to name,
        MediaStore.MediaColumns.MIME_TYPE to mimeType,
        MediaStore.MediaColumns.RELATIVE_PATH to relativePath,
        MediaStore.MediaColumns.BUCKET_DISPLAY_NAME to bucket,
    ),
    uri = uri,
)

/** A typical image discovery record; defaults mirror [imageRow]. */
fun record(
    id: Long,
    category: ContentCategory = ContentCategory.IMAGES,
    volumeName: String = "external_primary",
): MediaDiscoveryRecord = MediaDiscoveryRecord(
    category = category,
    volumeName = volumeName,
    mediaStoreId = id,
    stableKey = MediaDiscoveryRecord.stableKey(volumeName, id),
    relinkSignature = RelinkSignature.compute("DCIM/Camera/", "photo.jpg", 1_000_000, 2_000),
    contentUri = "content://media/external/images/media/$id",
    displayName = "photo.jpg",
    mimeType = "image/jpeg",
    sizeBytes = 1_000_000,
    dateAdded = 1_000,
    dateModified = 2_000,
    relativePath = "DCIM/Camera/",
    bucketDisplayName = "Camera",
    width = 1920,
    height = 1080,
    durationMs = null,
    title = null,
    artist = null,
    album = null,
    screenshotScore = null,
    isScreenshot = null,
)

/** Records every [DiscoveryEventSink] event for assertions. */
class RecordingSink : DiscoveryEventSink {
    private val queue = ConcurrentLinkedQueue<Map<String, Any?>>()
    override fun send(event: Map<String, Any?>) {
        queue.add(event)
    }

    fun events(): List<Map<String, Any?>> = queue.toList()

    fun batches(): Int = events().count { it["type"] == "discoveryBatch" }

    fun latestBatch(): Map<String, Any?> =
        events().last { it["type"] == "discoveryBatch" }

    fun latestBatchSequence(): Int = latestBatch()["sequence"] as Int

    fun latestBatchRecords(): List<MediaDiscoveryRecord> =
        (latestBatch()["records"] as List<*>).filterIsInstance<Map<*, *>>().map { row ->
            MediaDiscoveryRecord(
                category = ContentCategory.fromWire(row["category"] as String),
                volumeName = row["volumeName"] as String,
                mediaStoreId = row["mediaStoreId"] as Long,
                stableKey = row["stableKey"] as String,
                relinkSignature = row["relinkSignature"] as String?,
                contentUri = row["contentUri"] as String,
                displayName = row["displayName"] as String,
                mimeType = row["mimeType"] as String?,
                sizeBytes = row["sizeBytes"] as Long?,
                dateAdded = row["dateAdded"] as Long?,
                dateModified = row["dateModified"] as Long?,
                relativePath = row["relativePath"] as String?,
                bucketDisplayName = row["bucketDisplayName"] as String?,
                width = (row["width"] as Number?)?.toInt(),
                height = (row["height"] as Number?)?.toInt(),
                durationMs = row["durationMs"] as Long?,
                title = row["title"] as String?,
                artist = row["artist"] as String?,
                album = row["album"] as String?,
                screenshotScore = (row["screenshotScore"] as Number?)?.toInt(),
                isScreenshot = row["isScreenshot"] as Boolean?,
            )
        }
}

/** Deterministic paged querier whose pages never exceed what the test feeds it. */
class FakeQuerier(
    private val pagesByCategory: Map<ContentCategory, List<List<MediaDiscoveryRecord>>>,
    private val externalVolumes: List<String> = listOf("external_primary"),
    private val generations: Map<Pair<ContentCategory, String>, Long> = emptyMap(),
) : DiscoveryQuerier {
    val queries = ConcurrentLinkedQueue<QueryRequest>()
    private val counters = ConcurrentHashMap<Pair<ContentCategory, String>, Int>()

    val queryCount: Int get() = queries.size

    override fun volumes(): List<String> = externalVolumes

    override fun probeGeneration(category: ContentCategory, volumeName: String): Long? =
        generations[category to volumeName]

    override fun queryPage(request: QueryRequest): QueryPage {
        queries.add(request)
        val key = request.category to request.volumeName
        val pages = pagesByCategory[request.category] ?: emptyList()
        val index = counters.compute(key) { _, value -> (value ?: 0) + 1 }!! - 1
        if (index >= pages.size) {
            return QueryPage(emptyList(), hasMore = false, generationAfter = null, skippedCount = 0, lastBatchId = request.lastId)
        }
        val batch = pages[index]
        val isLast = index == pages.size - 1
        return QueryPage(
            records = batch,
            hasMore = !isLast,
            generationAfter = null,
            skippedCount = 0,
            lastBatchId = batch.lastOrNull()?.mediaStoreId,
        )
    }
}

/** Polls until [what] holds or fails after [timeoutMs]. */
fun awaitCondition(timeoutMs: Long = 5_000, what: () -> Boolean) {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (System.currentTimeMillis() < deadline) {
        if (what()) return
        Thread.sleep(10)
    }
    throw AssertionError("Condition not met within ${timeoutMs}ms")
}

/** Asserts [what] still does not hold after [sleepMs] milliseconds. */
fun assertStill(timeoutMs: Long, what: () -> Boolean) {
    Thread.sleep(timeoutMs)
    if (what()) throw AssertionError("Condition unexpectedly became true")
}