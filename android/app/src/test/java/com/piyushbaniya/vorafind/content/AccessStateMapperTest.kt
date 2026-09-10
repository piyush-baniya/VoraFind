package com.piyushbaniya.vorafind.content

import org.junit.Assert.assertEquals
import org.junit.Test

class AccessStateMapperTest {

    // Status query: no dialog is ever shown, so "denied" only appears when the
    // system suggests a rationale (i.e. a prior explicit denial).
    @Test
    fun `status query returns full when granted`() {
        assertEquals(ContentAccessState.FULL_ACCESS, AccessStateMapper.fromStatusQuery(true, false))
        assertEquals(ContentAccessState.FULL_ACCESS, AccessStateMapper.fromStatusQuery(true, true))
    }

    @Test
    fun `status query returns denied when blocked without rationale`() {
        assertEquals(ContentAccessState.DENIED, AccessStateMapper.fromStatusQuery(false, true))
    }

    @Test
    fun `status query returns no access when never granted and no rationale`() {
        assertEquals(ContentAccessState.NO_ACCESS, AccessStateMapper.fromStatusQuery(false, false))
    }

    // Request result: a failed request with no rationale means "don't ask again".
    @Test
    fun `request result maps full grant`() {
        assertEquals(ContentAccessState.FULL_ACCESS, AccessStateMapper.fromRequestResult(true, false))
    }

    @Test
    fun `request result maps plain denial`() {
        assertEquals(ContentAccessState.DENIED, AccessStateMapper.fromRequestResult(false, true))
    }

    @Test
    fun `request result maps permanent denial`() {
        assertEquals(
            ContentAccessState.PERMANENTLY_DENIED,
            AccessStateMapper.fromRequestResult(false, false),
        )
    }

    // Android 14+ visual media: full grant, selected-items-only grant, or none.
    @Test
    fun `visual status maps partial grant`() {
        assertEquals(
            ContentAccessState.PARTIAL_ACCESS,
            AccessStateMapper.visualStatus(false, true, true),
        )
    }

    @Test
    fun `visual request result maps user-selected grant`() {
        assertEquals(
            ContentAccessState.PARTIAL_ACCESS,
            AccessStateMapper.visualRequestResult(isFullGranted = false, isSelectedGranted = true, canAskAgain = true),
        )
    }

    @Test
    fun `visual status refuses to treat selection as full access`() {
        val status = AccessStateMapper.visualStatus(false, true, false)
        assertEquals(ContentAccessState.PARTIAL_ACCESS, status)
    }

    @Test
    fun `visual request result maps permanent denial`() {
        assertEquals(
            ContentAccessState.PERMANENTLY_DENIED,
            AccessStateMapper.visualRequestResult(false, false, false),
        )
    }
}