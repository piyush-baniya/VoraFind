package com.piyushbaniya.vorafind.discovery

import android.provider.MediaStore
import com.piyushbaniya.vorafind.content.ContentCategory
import java.util.concurrent.CancellationException

/**
 * Plays one MediaStore row at a time (no list materialization).
 *
 * The Android cursor implementation serves rows lazily; [RowSource] hides that
 * behind a pull interface so batching/shaping logic stays JVM-testable.
 */
fun interface RowSource {
    /** Next row, or null when the source is exhausted. */
    fun nextRow(): MediaStoreRow?
}

/**
 * Reads at most [batchSize] mapped records from a [RowSource] and reports whether
 * a further keyset page exists by peeking at most one extra row — so batches are
 * never larger than [batchSize] yet `hasMore` stays exact without a second query.
 *
 * Pure orchestration: per-row [RowMappingException] failures are counted and
 * skipped; cancellation is checked per row and raised as [CancellationException].
 *
 * Keyset advancement is [QueryPage.lastBatchId] — the `_ID` of the last row inside
 * the batch window — so a page whose rows all failed mapping still advances. The
 * peeking row (if any) is deliberately *not* used as the cursor: it must be
 * re-fetched by the next keyset query.
 */
object QueryPageAssembler {

    fun assemble(
        rows: RowSource,
        category: ContentCategory,
        volumeName: String,
        batchSize: Int,
        isCancelled: () -> Boolean,
    ): QueryPage {
        require(batchSize > 0) { "batchSize must be positive" }
        val records = ArrayList<MediaDiscoveryRecord>(batchSize)
        var batchCount = 0
        var skipped = 0
        var hasMore = false
        var lastBatchId: Long? = null
        while (true) {
            if (isCancelled()) throw CancellationException("Discovery cancelled")
            val row = rows.nextRow() ?: break
            val rowId = row.longOrNull(MediaStore.MediaColumns._ID)
            if (batchCount < batchSize) {
                batchCount++
                if (rowId != null) lastBatchId = rowId
                try {
                    records.add(MediaRowMapper.map(row, category, volumeName))
                } catch (e: RowMappingException) {
                    skipped++
                }
            } else {
                // Exactly one extra row to prove a further keyset page exists.
                hasMore = true
                break
            }
        }
        return QueryPage(
            records = records,
            hasMore = hasMore,
            generationAfter = null,
            skippedCount = skipped,
            lastBatchId = lastBatchId,
        )
    }
}