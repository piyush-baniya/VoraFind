package com.piyushbaniya.vorafind.discovery

import android.provider.MediaStore
import com.piyushbaniya.vorafind.content.ContentCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean

class QueryPageAssemblerTest {

    @Test
    fun `empty source yields an empty exhausted page`() {
        val page = QueryPageAssembler.assemble(
            RowSource { null },
            ContentCategory.IMAGES,
            "external_primary",
            batchSize = 500,
            isCancelled = { false },
        )
        assertTrue(page.records.isEmpty())
        assertFalse(page.hasMore)
        assertEquals(0, page.skippedCount)
        assertEquals(null, page.lastBatchId)
    }

    @Test
    fun `fewer rows than the batch are delivered without hasMore`() {
        val rows = listOf(imageRow(1), imageRow(2), imageRow(3))
        val page = assemble(rows, batchSize = 500)
        assertEquals(listOf(1L, 2L, 3L), page.records.map { it.mediaStoreId })
        assertFalse(page.hasMore)
        assertEquals(3L, page.lastBatchId)
    }

    @Test
    fun `exactly one batch has no hasMore`() {
        val rows = (1..500L).map { imageRow(it) }
        val page = assemble(rows, batchSize = 500)
        assertEquals(500, page.records.size)
        assertFalse(page.hasMore)
        assertEquals(500L, page.lastBatchId)
    }

    @Test
    fun `one extra row peeks into hasMore without growing the batch`() {
        val rows = (1..501L).map { imageRow(it) }
        val page = assemble(rows, batchSize = 500)
        assertEquals(500, page.records.size)
        assertTrue(page.hasMore)
        assertEquals(500L, page.lastBatchId)
    }

    @Test
    fun `multiple batches stay exact at every boundary`() {
        val all = (1..1234L).map { imageRow(it) }
        val first = assemble(all, batchSize = 500)
        assertEquals(500, first.records.size)
        assertTrue(first.hasMore)

        val remainder = assemble(all.drop(500), batchSize = 500)
        assertEquals(500, remainder.records.size)
        assertTrue(remainder.hasMore)
        assertEquals(1000L, remainder.lastBatchId)

        val tail = assemble(all.drop(1000), batchSize = 500)
        assertEquals(234, tail.records.size)
        assertFalse(tail.hasMore)
        assertEquals(1234L, tail.lastBatchId)
    }

    @Test
    fun `corrupt rows are skipped and counted without failing the page`() {
        // Force RowMappingException by removing the identity column.
        val corrupt = FakeRow(
            longs = emptyMap(),
            strings = mapOf(MediaStore.MediaColumns.DISPLAY_NAME to "bad.jpg"),
        )
        val rows = listOf(imageRow(1), corrupt, imageRow(2))
        val page = assemble(rows, batchSize = 500)
        assertEquals(listOf(1L, 2L), page.records.map { it.mediaStoreId })
        assertEquals(1, page.skippedCount)
        assertEquals(2L, page.lastBatchId)
    }

    @Test
    fun `fully skipped pages are counted and expose no keyset cursor`() {
        val corrupt = FakeRow(
            longs = emptyMap(),
            strings = mapOf(MediaStore.MediaColumns.DISPLAY_NAME to "bad.jpg"),
        )
        val rows = (1..500L).map { corrupt }
        val page = assemble(rows, batchSize = 500)
        assertTrue(page.records.isEmpty())
        assertFalse(page.hasMore)
        assertEquals(500, page.skippedCount)
        // Rows without identity cannot advance the keyset; the engine treats a
        // still-paged cursor with no lastBatchId as a scanner-level failure.
        assertEquals(null, page.lastBatchId)
    }

    @Test
    fun `cancellation aborts the page with CancellationException`() {
        val cancelled = AtomicBoolean(false)
        val rows = RowSource { cancelled.set(true); imageRow(1) }
        try {
            QueryPageAssembler.assemble(
                rows,
                ContentCategory.IMAGES,
                "external_primary",
                batchSize = 500,
                isCancelled = { cancelled.get() },
            )
            throw AssertionError("Expected CancellationException")
        } catch (e: CancellationException) {
            // expected
        }
    }

    private fun assemble(rows: List<MediaStoreRow>, batchSize: Int): QueryPage {
        var current = 0
        val source = RowSource {
            if (current < rows.size) rows[current++] else null
        }
        return QueryPageAssembler.assemble(source, ContentCategory.IMAGES, "external_primary", batchSize) { false }
    }
}