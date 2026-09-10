package com.piyushbaniya.vorafind.discovery

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RelinkSignatureTest {

    @Test
    fun `same metadata yields the same signature`() {
        val first = RelinkSignature.compute("DCIM/Camera/", "IMG_0001.jpg", 1_000_000L, 1_700_000_000_000)
        val second = RelinkSignature.compute("DCIM/Camera/", "IMG_0001.jpg", 1_000_000L, 1_700_000_000_000)
        assertEquals(first, second)
    }

    @Test
    fun `any tuple change yields a different signature`() {
        val baseline = RelinkSignature.compute("DCIM/Camera/", "IMG_0001.jpg", 1_000_000L, 1_700_000_000_000)
        assertNotEquals(baseline, RelinkSignature.compute("Pictures/", "IMG_0001.jpg", 1_000_000L, 1_700_000_000_000))
        assertNotEquals(baseline, RelinkSignature.compute("DCIM/Camera/", "IMG_0002.jpg", 1_000_000L, 1_700_000_000_000))
        assertNotEquals(baseline, RelinkSignature.compute("DCIM/Camera/", "IMG_0001.jpg", 2_000_000L, 1_700_000_000_000))
        assertNotEquals(baseline, RelinkSignature.compute("DCIM/Camera/", "IMG_0001.jpg", 1_000_000L, 1_700_000_000_001))
    }

    @Test
    fun `null metadata is stable`() {
        val withNulls = RelinkSignature.compute("DCIM/Camera/", null, null, null)
        assertEquals(
            withNulls,
            RelinkSignature.compute("DCIM/Camera/", null, null, null),
        )
    }

    @Test
    fun `null members normalize to the empty string`() {
        // The mapper never passes null display name (it coalesces to ""), so the
        // signature treats null and "" identically.
        assertEquals(
            RelinkSignature.compute("DCIM/Camera/", null, null, null),
            RelinkSignature.compute("DCIM/Camera/", "", null, null),
        )
    }

    @Test
    fun `returns null when relative path is unavailable`() {
        assertNull(RelinkSignature.compute(null, "IMG.jpg", 1L, 2L))
        assertNull(RelinkSignature.compute("  ", "IMG.jpg", 1L, 2L))
    }

    @Test
    fun `is a 64 character hex sha256`() {
        val signature = RelinkSignature.compute("DCIM/Camera/", "IMG.jpg", 1L, 2L)!!
        assertEquals(64, signature.length)
        assert(signature.matches(Regex("[0-9a-f]{64}")))
    }
}