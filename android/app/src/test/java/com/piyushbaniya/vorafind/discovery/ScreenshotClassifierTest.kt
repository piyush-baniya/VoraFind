package com.piyushbaniya.vorafind.discovery

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenshotClassifierTest {

    @Test
    fun `AOSP screenshot filename is a strong signal`() {
        val result = ScreenshotClassifier.classify(
            relativePath = "Pictures/",
            bucketDisplayName = "Pictures",
            displayName = "Screenshot_20250911-143022.png",
            mimeType = "image/png",
            sizeBytes = 800_000,
        )
        assertTrue(result.isScreenshot)
        assertEquals(100, result.score) // 60 + 10 capped
    }

    @Test
    fun `screenshot path mention is a strong signal without filename`() {
        val result = ScreenshotClassifier.classify(
            relativePath = "Pictures/Screenshots/",
            bucketDisplayName = "Screenshots",
            displayName = "IMG_0001.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1_000_000,
        )
        assertTrue(result.isScreenshot)
    }

    @Test
    fun `oem prefix alone is below threshold`() {
        val result = ScreenshotClassifier.classify(
            relativePath = "DCIM/",
            bucketDisplayName = "Camera",
            displayName = "Screenshot_2021-03-02-11-44-30_1.png",
            mimeType = "image/png",
            sizeBytes = 900_000,
        )
        assertEquals(35 + 10, result.score)
        assertFalse(result.isScreenshot)
    }

    @Test
    fun `normal camera photo is not a screenshot`() {
        val result = ScreenshotClassifier.classify(
            relativePath = "DCIM/Camera/",
            bucketDisplayName = "Camera",
            displayName = "IMG_20250911_143022.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 4_000_000,
        )
        assertEquals(10, result.score)
        assertFalse(result.isScreenshot)
    }

    @Test
    fun `size outside snapshot range drops the low signal`() {
        val result = ScreenshotClassifier.classify(
            relativePath = "DCIM/Camera/",
            bucketDisplayName = "Camera",
            displayName = "IMG_0001.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 30_000,
        )
        assertEquals(0, result.score)
        assertFalse(result.isScreenshot)
    }

    @Test
    fun `matching is case insensitive`() {
        val result = ScreenshotClassifier.classify(
            relativePath = "DCIM/",
            bucketDisplayName = "Pictures/SCREENSHOTS",
            displayName = "whatever.jpg",
            mimeType = "image/webp",
            sizeBytes = 1_000_000,
        )
        assertTrue(result.isScreenshot)
    }

    @Test
    fun `all nulls and empties classify as not a screenshot`() {
        val result = ScreenshotClassifier.classify(null, null, null, null, null)
        assertEquals(0, result.score)
        assertFalse(result.isScreenshot)
    }

    @Test
    fun `score is never misleading about disjoint weak signals`() {
        val result = ScreenshotClassifier.classify(
            relativePath = null,
            bucketDisplayName = null,
            displayName = "screenshot.jpg",
            mimeType = "image/jpeg",
            sizeBytes = 1_000_000,
        )
        // OEM prefix "screenshot." is NOT in the prefix list; only the size signal fires.
        assertEquals(10, result.score)
        assertFalse(result.isScreenshot)
    }
}