package com.piyushbaniya.vorafind.content

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CapabilityMapperTest {

    @Test
    fun `full access implies all read flags`() {
        val flags = CapabilityMapper.accessFlags(ContentAccessState.FULL_ACCESS)
        assertTrue(flags.canQuery)
        assertTrue(flags.canReadAll)
        assertTrue(flags.canReadSelected)
    }

    @Test
    fun `partial access never enables full read`() {
        val flags = CapabilityMapper.accessFlags(ContentAccessState.PARTIAL_ACCESS)
        assertTrue(flags.canQuery)
        assertFalse(flags.canReadAll)
        assertTrue(flags.canReadSelected)
    }

    @Test
    fun `no access disables everything`() {
        for (state in listOf(
            ContentAccessState.NO_ACCESS,
            ContentAccessState.DENIED,
            ContentAccessState.PERMANENTLY_DENIED,
        )) {
            val flags = CapabilityMapper.accessFlags(state)
            assertFalse(flags.canQuery)
            assertFalse(flags.canReadAll)
            assertFalse(flags.canReadSelected)
        }
    }

    @Test
    fun `not required can query but not read`() {
        val flags = CapabilityMapper.accessFlags(ContentAccessState.NOT_REQUIRED)
        assertTrue(flags.canQuery)
        assertFalse(flags.canReadAll)
        assertFalse(flags.canReadSelected)
    }

    @Test
    fun `capabilities payload carries contract version and platform`() {
        val capabilities = CapabilityMapper.capabilities(
            apiLevel = 36,
            states = mapOf(
                ContentCategory.DOCUMENTS to ContentAccessState.PARTIAL_ACCESS,
            ),
            externalVolumes = emptyList(),
        )
        assertEquals(1, capabilities["contractVersion"])
        assertEquals("android", capabilities["platform"])
        assertEquals(36, capabilities["apiLevel"])
    }

    @Test
    fun `media store generation requires API 30`() {
        assertEquals(
            false,
            CapabilityMapper.capabilities(
                apiLevel = 29,
                states = emptyMap(),
                externalVolumes = emptyList(),
            )["mediaStoreGenerationSupported"],
        )
        assertEquals(
            true,
            CapabilityMapper.capabilities(
                apiLevel = 30,
                states = emptyMap(),
                externalVolumes = emptyList(),
            )["mediaStoreGenerationSupported"],
        )
    }

    @Test
    fun `partial media access requires API 34`() {
        assertEquals(
            false,
            CapabilityMapper.capabilities(
                apiLevel = 33,
                states = emptyMap(),
                externalVolumes = emptyList(),
            )["partialMediaAccessSupported"],
        )
        assertEquals(
            true,
            CapabilityMapper.capabilities(
                apiLevel = 34,
                states = emptyMap(),
                externalVolumes = emptyList(),
            )["partialMediaAccessSupported"],
        )
    }

    @Test
    fun `categories are always reported in a fixed order`() {
        val capabilities = CapabilityMapper.capabilities(
            apiLevel = 36,
            states = mapOf(
                ContentCategory.IMAGES to ContentAccessState.FULL_ACCESS,
                ContentCategory.VIDEOS to ContentAccessState.NO_ACCESS,
                ContentCategory.AUDIO to ContentAccessState.DENIED,
                ContentCategory.DOCUMENTS to ContentAccessState.PARTIAL_ACCESS,
            ),
            externalVolumes = listOf("external_primary"),
        )

        @Suppress("UNCHECKED_CAST")
        val categories = capabilities["categories"] as List<Map<String, Any?>>
        assertEquals(listOf("images", "videos", "audio", "documents"), categories.map { it["category"] })

        @Suppress("UNCHECKED_CAST")
        val documents = categories.last()
        assertEquals("partialAccess", documents["state"])
        assertEquals(false, documents["canReadAll"])
        assertTrue(documents["canReadSelected"] as Boolean)
    }

    @Test
    fun `external volumes are passed through sorted`() {
        val capabilities = CapabilityMapper.capabilities(
            apiLevel = 36,
            states = emptyMap(),
            externalVolumes = listOf("0", "external_primary"),
        )
        @Suppress("UNCHECKED_CAST")
        assertEquals(
            listOf("0", "external_primary"),
            capabilities["externalVolumes"] as List<String>,
        )
    }
}