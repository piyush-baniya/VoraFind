package com.piyushbaniya.vorafind.discovery

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.provider.MediaStore
import com.piyushbaniya.vorafind.content.ContentCategory

/**
 * Queries one bounded keyset page of records. Implemented by [MediaStoreQuerier]
 * on device and by fakes in JVM tests.
 */
interface DiscoveryQuerier {
    /** Available external MediaStore volumes in deterministic order. */
    fun volumes(): List<String>

    /** One page: up to [QueryRequest.batchSize] records plus hasMore/exhaustion. */
    fun queryPage(request: QueryRequest): QueryPage
}

/**
 * MediaStore-owned enumeration (architecture §6): typed collections per category,
 * API-gated volumes/projections/selection, keyset paging, no filesystem access.
 *
 * Runs on the discovery engine's single background thread; never touches the UI.
 */
class MediaStoreQuerier(private val context: Context) : DiscoveryQuerier {

    private val apiLevel = Build.VERSION.SDK_INT
    private val signal = CancellationSignal()

    /** Before API 29 there is no volume API; a single nominal volume is used. */
    override fun volumes(): List<String> =
        if (apiLevel >= Build.VERSION_CODES.Q) {
            try {
                MediaStore.getExternalVolumeNames(context).sorted()
            } catch (_: Exception) {
                listOf(DEFAULT_VOLUME)
            }
        } else {
            listOf(DEFAULT_VOLUME)
        }

    override fun queryPage(request: QueryRequest): QueryPage {
        val collectionUri = collectionUriFor(request.category, request.volumeName)
        val cursor = context.contentResolver.query(
            collectionUri,
            projectionFor(request.category),
            selectionFor(request.lastId),
            selectionArgsFor(request.lastId),
            SORT_ORDER_BY_ID,
            signal,
        ) ?: return QueryPage(
            records = emptyList(),
            hasMore = false,
            generationAfter = null,
            skippedCount = 0,
            lastBatchId = request.lastId,
        )

        cursor.use {
            val page = QueryPageAssembler.assemble(
                rows = CursorRowSource(it, collectionUri),
                category = request.category,
                volumeName = request.volumeName,
                batchSize = request.batchSize,
                isCancelled = request.isCancelled,
            )
            return page.copy(generationAfter = generationOf(collectionUri, request.category))
        }
    }

    private fun collectionUriFor(category: ContentCategory, volumeName: String): Uri {
        val legacyBase = when (category) {
            ContentCategory.IMAGES -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            ContentCategory.VIDEOS -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            ContentCategory.AUDIO -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            ContentCategory.DOCUMENTS -> throw IllegalArgumentException("Documents are SAF-scoped, not MediaStore.")
        }
        return if (apiLevel >= Build.VERSION_CODES.Q) {
            when (category) {
                ContentCategory.IMAGES -> MediaStore.Images.Media.getContentUri(volumeName)
                ContentCategory.VIDEOS -> MediaStore.Video.Media.getContentUri(volumeName)
                ContentCategory.AUDIO -> MediaStore.Audio.Media.getContentUri(volumeName)
                ContentCategory.DOCUMENTS -> legacyBase
            }
        } else {
            legacyBase
        }
    }

    /** Explicit projections only — columns we actually emit (architecture §6.2). */
    private fun projectionFor(category: ContentCategory): Array<String> {
        val columns = mutableListOf(MediaStore.MediaColumns._ID)
        columns += MediaStore.MediaColumns.DISPLAY_NAME
        columns += MediaStore.MediaColumns.MIME_TYPE
        columns += MediaStore.MediaColumns.SIZE
        columns += MediaStore.MediaColumns.DATE_ADDED
        columns += MediaStore.MediaColumns.DATE_MODIFIED
        columns += MediaStore.MediaColumns.BUCKET_DISPLAY_NAME
        columns += MediaStore.MediaColumns.DURATION
        when (category) {
            ContentCategory.IMAGES, ContentCategory.VIDEOS -> {
                columns += MediaStore.MediaColumns.WIDTH
                columns += MediaStore.MediaColumns.HEIGHT
            }
            ContentCategory.AUDIO -> {
                columns += MediaStore.Audio.AudioColumns.TITLE
                columns += MediaStore.Audio.AudioColumns.ARTIST
                columns += MediaStore.Audio.AudioColumns.ALBUM
            }
            ContentCategory.DOCUMENTS -> Unit
        }
        if (apiLevel >= Build.VERSION_CODES.Q) {
            columns += MediaStore.MediaColumns.RELATIVE_PATH
            columns += MediaStore.MediaColumns.VOLUME_NAME
        }
        return columns.toTypedArray()
    }

    /**
     * `IS_PENDING = 0` (API 29+) and `IS_TRASHED = 0` (API 30+) keep pending and
     * trashed rows out; keyset cursor `_ID > ?` keeps pages stable mid-scan.
     */
    private fun selectionFor(lastId: Long): String? {
        val parts = mutableListOf<String>()
        when {
            apiLevel >= Build.VERSION_CODES.R -> {
                parts += "${MediaStore.MediaColumns.IS_PENDING}=0"
                parts += "${MediaStore.MediaColumns.IS_TRASHED}=0"
            }
            apiLevel >= Build.VERSION_CODES.Q -> {
                parts += "${MediaStore.MediaColumns.IS_PENDING}=0"
            }
        }
        if (lastId > 0L) {
            parts += "${MediaStore.MediaColumns._ID} > ?"
        }
        return parts.joinToString(separator = " AND ").ifEmpty { null }
    }

    private fun selectionArgsFor(lastId: Long): Array<String>? =
        if (lastId > 0L) arrayOf(lastId.toString()) else null

    /**
     * MediaStore generation snapshot for incremental sync (architecture §15).
     * API 34+ surfaces as an opaque-string overload; the return value is still a
     * monotonic integer-like generation token. Never used for delta scanning.
     */
    private fun generationOf(collectionUri: Uri, category: ContentCategory): Long? {
        if (apiLevel < Build.VERSION_CODES.R) return null
        if (category == ContentCategory.DOCUMENTS) return null
        return try {
            MediaStore.getGeneration(context, collectionUri.toString())
        } catch (_: Exception) {
            null
        }
    }

    private companion object {
        const val DEFAULT_VOLUME = "external_primary"
        const val SORT_ORDER_BY_ID = "${MediaStore.MediaColumns._ID} ASC"
    }
}

/** Pulls one cursor row at a time; column indices are resolved once per cursor. */
private class CursorRowSource(
    private val cursor: Cursor,
    private val baseUri: Uri,
) : RowSource {
    private val columnIndex: Map<String, Int> =
        buildMap {
            for ((index, name) in cursor.columnNames.withIndex()) put(name, index)
        }

    override fun nextRow(): MediaStoreRow? =
        if (cursor.moveToNext()) CursorMediaStoreRow(cursor, baseUri, columnIndex) else null
}

private class CursorMediaStoreRow(
    private val cursor: Cursor,
    private val baseUri: Uri,
    private val columnIndex: Map<String, Int>,
) : MediaStoreRow {

    override fun longOrNull(column: String): Long? =
        indexOf(column)?.takeIf { !cursor.isNull(it) }?.let {
            try {
                cursor.getLong(it)
            } catch (_: Exception) {
                null
            }
        }

    override fun stringOrNull(column: String): String? =
        indexOf(column)?.takeIf { !cursor.isNull(it) }?.let {
            try {
                cursor.getString(it)
            } catch (_: Exception) {
                null
            }
        }

    override fun contentUri(): String {
        val id = indexOf(MediaStore.MediaColumns._ID) ?: return ""
        return try {
            android.content.ContentUris.withAppendedId(baseUri, cursor.getLong(id)).toString()
        } catch (_: Exception) {
            ""
        }
    }

    private fun indexOf(column: String): Int? = columnIndex[column]?.takeIf { it >= 0 }
}