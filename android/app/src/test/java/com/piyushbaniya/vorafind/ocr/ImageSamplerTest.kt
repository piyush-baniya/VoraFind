package com.piyushbaniya.vorafind.ocr

import org.junit.Assert.assertEquals
import org.junit.Test

class ImageSamplerTest {

    @Test
    fun `small images keep a sample size of one`() {
        assertEquals(1, ImageSampler.inSampleSizeFor(1920, 1080, 2048))
        assertEquals(1, ImageSampler.inSampleSizeFor(2047, 2047, 2048))
    }

    @Test
    fun `dimensions at or below the limit decode without downsampling`() {
        assertEquals(1, ImageSampler.inSampleSizeFor(2048, 2048, 2048))
        assertEquals(1, ImageSampler.inSampleSizeFor(2000, 3000, 4096))
    }

    @Test
    fun `oversized photos downsample below the limit`() {
        // 4000x3000 -> sample 2 -> 2000x1500 <= 2048
        assertEquals(2, ImageSampler.inSampleSizeFor(4000, 3000, 2048))
        // 4096x4096 -> sample 2 -> 2048x2048 (exact power-of-two target)
        assertEquals(2, ImageSampler.inSampleSizeFor(4096, 4096, 2048))
        // Dominant axis drives the sample.
        assertEquals(4, ImageSampler.inSampleSizeFor(8000, 4000, 2048))
    }

    @Test
    fun `every edge leaves both axes within the requested maximum`() {
        val cases = listOf(
            Triple(2060, 1000, 2),
            Triple(30000, 30000, 16),
            Triple(2049, 2049, 2),
            Triple(1, 5000, 4),
            Triple(5000, 1, 4),
        )
        for ((width, height, expected) in cases) {
            val sample = ImageSampler.inSampleSizeFor(width, height, 2048)
            assertEquals(expected, sample)
            // ceil(width/sample) <= 2048 && ceil(height/sample) <= 2048
            assertEquals(true, (width + sample - 1) / sample <= 2048)
            assertEquals(true, (height + sample - 1) / sample <= 2048)
        }
    }

    @Test
    fun `a custom maximum dimension is honoured`() {
        assertEquals(2, ImageSampler.inSampleSizeFor(900, 900, 512))
        assertEquals(4, ImageSampler.inSampleSizeFor(2000, 2000, 512))
    }

    @Test
    fun `invalid inputs yield a sample of one`() {
        assertEquals(1, ImageSampler.inSampleSizeFor(0, 100, 2048))
        assertEquals(1, ImageSampler.inSampleSizeFor(100, -5, 2048))
        assertEquals(1, ImageSampler.inSampleSizeFor(100, 100, 0))
    }
}