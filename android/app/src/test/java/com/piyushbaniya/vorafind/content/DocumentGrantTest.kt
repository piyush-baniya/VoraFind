package com.piyushbaniya.vorafind.content

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentGrantTest {

    @Test
    fun `read-only grant never reports write capability`() {
        val grant = DocumentGrant(
            uri = "content://authority/tree/folder",
            displayName = "Documents",
            persisted = true,
            readable = true,
            writable = false,
        )
        assertEquals("content://authority/tree/folder", grant.uri)
        assertEquals("Documents", grant.displayName)
        assertTrue(grant.persisted)
        assertTrue(grant.readable)
        assertFalse(grant.writable)
    }

    @Test
    fun `non-persisted grant keeps display metadata`() {
        val grant = DocumentGrant(
            uri = "content://authority/tree/other",
            displayName = "Downloads",
            persisted = false,
            readable = true,
            writable = false,
        )
        assertEquals("Downloads", grant.displayName)
        assertFalse(grant.persisted)
    }

    @Test
    fun `toMap exposes the bridge contract fields`() {
        val map = DocumentGrant(
            uri = "content://authority/tree/folder",
            displayName = "Downloads",
            persisted = false,
            readable = true,
            writable = false,
        ).toMap()

        assertEquals("content://authority/tree/folder", map["uri"])
        assertEquals("Downloads", map["displayName"])
        assertEquals(false, map["persisted"])
        assertEquals(true, map["readable"])
        assertEquals(false, map["writable"])
    }
}