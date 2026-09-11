package com.piyushbaniya.vorafind.discovery

import com.piyushbaniya.vorafind.content.ContentAccessState
import com.piyushbaniya.vorafind.content.ContentCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DiscoveryEngineTest {

    private fun engine(
        querier: DiscoveryQuerier,
        accessFor: (ContentCategory) -> ContentAccessState = { ContentAccessState.FULL_ACCESS },
    ) = DiscoveryEngine(querier = querier, accessFor = accessFor)

    @Test
    fun `empty library completes immediately with zero records`() {
        val sink = RecordingSink()
        val engine = engine(FakeQuerier(emptyMap()))
        engine.attachSink(sink)

        val result = engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES)))
        assertTrue(result.accepted)
        assertEquals(CategoryStartStatus.STARTED, result.categories.single().status)

        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
        val completed = sink.events().last { it["type"] == "discoveryCompleted" }
        assertEquals(0, completed["batchesSent"])
        assertEquals(0L, completed["recordsDiscovered"])
    }

    @Test
    fun `window one delays the second page until an explicit ack`() {
        val sink = RecordingSink()
        val engine = engine(
            FakeQuerier(
                mapOf(
                    ContentCategory.IMAGES to listOf(
                        listOf(record(1), record(2)),
                        listOf(record(3)),
                    ),
                ),
            ),
        )
        engine.attachSink(sink)
        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES))).accepted)

        awaitCondition { sink.batches() == 1 }
        assertEquals(
            listOf(1L, 2L),
            sink.latestBatchRecords().map { it.mediaStoreId },
        )
        assertStill(200L) { sink.batches() == 2 }

        assertTrue(engine.ackBatch(sink.latestBatchSequence()))
        awaitCondition { sink.batches() == 2 }
        assertEquals(listOf(3L), sink.latestBatchRecords().map { it.mediaStoreId })
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }

        val completed = sink.events().last { it["type"] == "discoveryCompleted" }
        assertEquals(3L, completed["recordsDiscovered"])
        assertEquals(2, completed["batchesSent"])
    }

    @Test
    fun `unknown and duplicate acks are rejected`() {
        val sink = RecordingSink()
        val engine = engine(
            FakeQuerier(
                mapOf(
                    ContentCategory.IMAGES to listOf(
                        listOf(record(1)),
                        listOf(record(2)),
                    ),
                ),
            ),
        )
        engine.attachSink(sink)
        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES))).accepted)

        assertFalse(engine.ackBatch(42))
        awaitCondition { sink.batches() == 1 }
        val sequence = sink.latestBatchSequence()
        assertTrue(engine.ackBatch(sequence))
        assertFalse(engine.ackBatch(sequence))
        awaitCondition { sink.batches() == 2 }
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
    }

    @Test
    fun `cancel while awaiting ack cancels the session and disables late acks`() {
        val sink = RecordingSink()
        val engine = engine(
            FakeQuerier(
                mapOf(
                    ContentCategory.IMAGES to listOf(listOf(record(1)), listOf(record(2))),
                ),
            ),
        )
        engine.attachSink(sink)
        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES))).accepted)
        awaitCondition { sink.batches() == 1 }
        val sequence = sink.latestBatchSequence()

        assertTrue(engine.cancel())
        awaitCondition { engine.status().state == DiscoveryState.CANCELLED }

        val cancelled = sink.events().last { it["type"] == "discoveryCancelled" }
        assertEquals(1L, cancelled["recordsDiscovered"])
        assertFalse(engine.ackBatch(sequence))
        assertEquals(1, sink.batches())
    }

    @Test
    fun `cancel is idempotent and never throws in terminal states`() {
        val engine = engine(FakeQuerier(mapOf(ContentCategory.IMAGES to listOf(listOf(record(1))))))
        assertFalse(engine.cancel())
        assertFalse(engine.cancel())
    }

    @Test
    fun `start is rejected while running`() {
        val sink = RecordingSink()
        val engine = engine(
            FakeQuerier(
                mapOf(ContentCategory.IMAGES to listOf(listOf(record(1)), listOf(record(2)))),
            ),
        )
        engine.attachSink(sink)
        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES))).accepted)
        awaitCondition { sink.batches() == 1 }

        val second = engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES)))
        assertFalse(second.accepted)
        assertEquals("busy", second.code)

        engine.cancel()
        awaitCondition { engine.status().state == DiscoveryState.CANCELLED }
    }

    @Test
    fun `start is rejected when no event listener is attached`() {
        val engine = engine(FakeQuerier(emptyMap()))
        val result = engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES)))
        assertFalse(result.accepted)
        assertEquals("eventListenerNotAttached", result.code)
        assertEquals(DiscoveryState.IDLE, engine.status().state)
    }

    @Test
    fun `start is rejected for an empty category list`() {
        val engine = engine(FakeQuerier(emptyMap()))
        engine.attachSink(RecordingSink())
        val result = engine.start(DiscoveryOptions(emptyList()))
        assertFalse(result.accepted)
        assertEquals("invalidArguments", result.code)
        assertEquals(DiscoveryState.IDLE, engine.status().state)
    }

    @Test
    fun `unavailable categories are reported and never scanned`() {
        val querier = FakeQuerier(emptyMap())
        val engine = engine(querier, accessFor = { ContentAccessState.NO_ACCESS })
        val sink = RecordingSink()
        engine.attachSink(sink)

        val result = engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES)))
        assertTrue(result.accepted)
        assertEquals(CategoryStartStatus.UNAVAILABLE, result.categories.single().status)

        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
        assertTrue(querier.queries.isEmpty())
        val completed = sink.events().last { it["type"] == "discoveryCompleted" }
        assertEquals(emptyList<Any?>(), completed["categories"])
    }

    @Test
    fun `documents are never scanned via MediaStore`() {
        val querier = FakeQuerier(emptyMap())
        val engine = engine(querier)
        val sink = RecordingSink()
        engine.attachSink(sink)

        val result = engine.start(DiscoveryOptions(listOf(ContentCategory.DOCUMENTS)))
        assertTrue(result.accepted)
        assertEquals(CategoryStartStatus.UNAVAILABLE, result.categories.single().status)
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
        assertTrue(querier.queries.isEmpty())
    }

    @Test
    fun `partial access reports partial scope on start and events`() {
        val sink = RecordingSink()
        val engine = engine(
            FakeQuerier(mapOf(ContentCategory.IMAGES to listOf(listOf(record(1))))),
            accessFor = { ContentAccessState.PARTIAL_ACCESS },
        )
        engine.attachSink(sink)

        val result = engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES)))
        assertEquals(CategoryStartStatus.PARTIAL, result.categories.single().status)
        assertEquals(AccessScope.PARTIAL, result.categories.single().accessScope)

        awaitCondition { sink.batches() == 1 }
        assertEquals("partial", sink.latestBatch()["accessScope"])
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
    }

    @Test
    fun `scanner failure ends the session with a typed error`() {
        val failing = object : DiscoveryQuerier {
            override fun volumes(): List<String> = listOf("external_primary")
            override fun queryPage(request: QueryRequest): QueryPage =
                throw RuntimeException("disk blip")
        }
        val sink = RecordingSink()
        val engine = engine(failing)
        engine.attachSink(sink)

        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES))).accepted)
        awaitCondition { engine.status().state == DiscoveryState.FAILED }
        val error = sink.events().last { it["type"] == "discoveryError" }
        assertEquals("scannerFailed", error["code"])
        assertEquals(DiscoveryState.FAILED, engine.status().state)
    }

    @Test
    fun `a cursor that never advances is treated as a scanner failure`() {
        val stuck = object : DiscoveryQuerier {
            override fun volumes(): List<String> = listOf("external_primary")
            override fun queryPage(request: QueryRequest): QueryPage =
                QueryPage(emptyList(), hasMore = true, generationAfter = null, skippedCount = 500, lastBatchId = null)
        }
        val sink = RecordingSink()
        val engine = engine(stuck)
        engine.attachSink(sink)

        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES))).accepted)
        awaitCondition { engine.status().state == DiscoveryState.FAILED }
        val error = sink.events().last { it["type"] == "discoveryError" }
        assertEquals("scannerFailed", error["code"])
    }

    @Test
    fun `multiple volumes are scanned in the querier order`() {
        val sink = RecordingSink()
        val querier = FakeQuerier(
            mapOf(ContentCategory.IMAGES to listOf(listOf(record(1, volumeName = "external_primary")))),
            externalVolumes = listOf("external_primary", "SD Card"),
        )
        val engine = engine(querier)
        engine.attachSink(sink)

        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES))).accepted)
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
        val started = sink.events().filter { it["type"] == "discoveryStarted" }
        assertEquals(listOf("external_primary", "SD Card"), started.map { it["volume"] })
        // Second volume has no pages: engine queries it and completes.
        assertTrue(querier.queryCount >= 2)
    }

    @Test
    fun `status reflects final totals after the ack-gated run completes`() {
        val sink = RecordingSink()
        val engine = engine(
            FakeQuerier(
                mapOf(
                    ContentCategory.IMAGES to listOf(
                        listOf(record(1), record(2)),
                        listOf(record(3)),
                    ),
                ),
            ),
        )
        engine.attachSink(sink)
        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES))).accepted)
        awaitCondition { sink.batches() == 1 }
        assertTrue(engine.ackBatch(sink.latestBatchSequence()))

        // After the first (gating) batch the progress event carries running totals,
        // independent of later batches — a race-free mid-run snapshot.
        awaitCondition { sink.events().any { it["type"] == "discoveryProgress" && it["recordsDiscovered"] == 2L } }
        val progress = sink.events().last { it["type"] == "discoveryProgress" && it["recordsDiscovered"] == 2L }
        assertEquals(2L, progress["recordsDiscovered"])
        assertEquals(1, progress["batchesSent"])
        assertEquals(1, progress["batchesRemaining"])

        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
        assertEquals(3L, engine.status().recordsDiscovered)
        assertEquals(2, engine.status().batchesSent)
        assertEquals(2, sink.batches())
    }

    @Test
    fun `volumes filter restricts the plans that are scanned`() {
        val sink = RecordingSink()
        val querier = FakeQuerier(
            mapOf(ContentCategory.IMAGES to listOf(listOf(record(1, volumeName = "external_primary")))),
            externalVolumes = listOf("external_primary", "SD Card"),
        )
        val engine = engine(querier)
        engine.attachSink(sink)

        val result = engine.start(
            DiscoveryOptions(listOf(ContentCategory.IMAGES), volumes = listOf("external_primary")),
        )
        assertTrue(result.accepted)
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
        val started = sink.events().filter { it["type"] == "discoveryStarted" }
        assertEquals(listOf("external_primary"), started.map { it["volume"] })
    }

    @Test
    fun `volumes filter never widens beyond the available volumes`() {
        val sink = RecordingSink()
        val querier = FakeQuerier(
            mapOf(ContentCategory.IMAGES to listOf(listOf(record(1, volumeName = "external_primary")))),
            externalVolumes = listOf("external_primary"),
        )
        val engine = engine(querier)
        engine.attachSink(sink)

        val result = engine.start(
            DiscoveryOptions(listOf(ContentCategory.IMAGES), volumes = listOf("external_primary", "Ghost Volume")),
        )
        assertTrue(result.accepted)
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
        val started = sink.events().filter { it["type"] == "discoveryStarted" }
        assertEquals(listOf("external_primary"), started.map { it["volume"] })
    }

    @Test
    fun `an empty volume filter behaves like scanning every volume`() {
        val sink = RecordingSink()
        val querier = FakeQuerier(
            mapOf(ContentCategory.IMAGES to listOf(listOf(record(1, volumeName = "external_primary")))),
            externalVolumes = listOf("external_primary", "SD Card"),
        )
        val engine = engine(querier)
        engine.attachSink(sink)

        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES), volumes = emptyList())).accepted)
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
        val started = sink.events().filter { it["type"] == "discoveryStarted" }
        assertEquals(listOf("external_primary", "SD Card"), started.map { it["volume"] })
    }

    @Test
    fun `probe generation is forwarded to the querier`() {
        val querier = FakeQuerier(
            emptyMap(),
            generations = mapOf(ContentCategory.IMAGES to "external_primary" to 42L),
        )
        val engine = engine(querier)
        assertEquals(42L, engine.probeGeneration(ContentCategory.IMAGES, "external_primary"))
        assertNull(engine.probeGeneration(ContentCategory.IMAGES, "unknown_volume"))
        assertNull(engine.probeGeneration(ContentCategory.DOCUMENTS, "external_primary"))
    }

    @Test
    fun `a completed session can be started again`() {
        val sink = RecordingSink()
        val querier = FakeQuerier(mapOf(ContentCategory.IMAGES to listOf(listOf(record(1)))))
        val engine = engine(querier)
        engine.attachSink(sink)

        assertTrue(engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES))).accepted)
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
        val queriesAfterFirst = querier.queryCount

        val again = engine.start(DiscoveryOptions(listOf(ContentCategory.IMAGES)))
        assertTrue(again.accepted)
        awaitCondition { querier.queryCount > queriesAfterFirst }
        awaitCondition { engine.status().state == DiscoveryState.COMPLETED }
    }
}