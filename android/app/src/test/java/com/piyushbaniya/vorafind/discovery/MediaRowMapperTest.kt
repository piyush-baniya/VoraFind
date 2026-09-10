package com.piyushbaniya.vorafind.discovery

import android.provider.MediaStore
import com.piyushbaniya.vorafind.content.ContentCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class MediaRowMapperTest {

    @Test
    fun `maps an image row fully`() {
        val row = imageRow(id = 42, name = "IMG_0042.jpg")
        val mapped = MediaRowMapper.map(row, ContentCategory.IMAGES, "external_primary")

        assertEquals(ContentCategory.IMAGES, mapped.category)
        assertEquals("external_primary", mapped.volumeName)
        assertEquals(42L, mapped.mediaStoreId)
        assertEquals("external_primary:42", mapped.stableKey)
        assertEquals("IMG_0042.jpg", mapped.displayName)
        assertEquals("content://media/external/images/media/42", mapped.contentUri)
        assertEquals("image/jpeg", mapped.mimeType)
        assertEquals(1_000_000L, mapped.sizeBytes)
        assertEquals(1_042L, mapped.dateAdded)
        assertEquals(2_042L, mapped.dateModified)
        assertEquals("DCIM/Camera/", mapped.relativePath)
        assertEquals("Camera", mapped.bucketDisplayName)
        assertEquals(1920, mapped.width)
        assertEquals(1080, mapped.height)
        assertEquals(10, mapped.screenshotScore!!)
        assertNull(mapped.durationMs)
        assertNull(mapped.title)
        assertNull(mapped.artist)
        assertNull(mapped.album)
    }

    @Test
    fun `maps an audio row with audio-only fields and no dimensions`() {
        val row = FakeRow(
            longs = mapOf(
                MediaStore.MediaColumns._ID to 7L,
                MediaStore.MediaColumns.SIZE to 5_000_000L,
                MediaStore.MediaColumns.DURATION to 180_000L,
            ),
            strings = mapOf(
                MediaStore.MediaColumns.DISPLAY_NAME to "track.mp3",
                MediaStore.MediaColumns.MIME_TYPE to "audio/mpeg",
                MediaStore.MediaColumns.RELATIVE_PATH to "Music/",
                MediaStore.Audio.AudioColumns.TITLE to "My Song",
                MediaStore.Audio.AudioColumns.ARTIST to "An Artist",
                MediaStore.Audio.AudioColumns.ALBUM to "The Album",
            ),
            uri = "content://media/external/audio/media/7",
        )
        val mapped = MediaRowMapper.map(row, ContentCategory.AUDIO, "external_primary")

        assertEquals(ContentCategory.AUDIO, mapped.category)
        assertEquals("My Song", mapped.title)
        assertEquals("An Artist", mapped.artist)
        assertEquals("The Album", mapped.album)
        assertEquals(180_000L, mapped.durationMs)
        assertNull(mapped.width)
        assertNull(mapped.height)
        assertNull(mapped.screenshotScore)
        assertNull(mapped.isScreenshot)
    }

    @Test
    fun `video rows keep dimensions and duration`() {
        val row = FakeRow(
            longs = mapOf(
                MediaStore.MediaColumns._ID to 9L,
                MediaStore.MediaColumns.WIDTH to 3840L,
                MediaStore.MediaColumns.HEIGHT to 2160L,
                MediaStore.MediaColumns.DURATION to 60_000L,
            ),
            strings = mapOf(
                MediaStore.MediaColumns.DISPLAY_NAME to "clip.mp4",
                MediaStore.MediaColumns.MIME_TYPE to "video/mp4",
            ),
            uri = "content://media/external/video/media/9",
        )
        val mapped = MediaRowMapper.map(row, ContentCategory.VIDEOS, "external_primary")

        assertEquals(3840, mapped.width)
        assertEquals(2160, mapped.height)
        assertEquals(60_000L, mapped.durationMs)
        assertNull(mapped.title)
        assertNull(mapped.artist)
        assertNull(mapped.album)
        assertNull(mapped.screenshotScore)
    }

    @Test
    fun `missing optional columns degrade to null`() {
        val row = FakeRow(
            longs = mapOf(MediaStore.MediaColumns._ID to 3L),
            strings = mapOf(MediaStore.MediaColumns.DISPLAY_NAME to "bare.jpg"),
        )
        val mapped = MediaRowMapper.map(row, ContentCategory.IMAGES, "external_primary")

        assertEquals(3L, mapped.mediaStoreId)
        assertNull(mapped.mimeType)
        assertNull(mapped.sizeBytes)
        assertNull(mapped.relativePath)
        assertNull(mapped.width)
        assertNull(mapped.height)
        assertNull(mapped.relinkSignature)
    }

    @Test
    fun `row without identity raises RowMappingException`() {
        val row = FakeRow(mapOf(), mapOf(MediaStore.MediaColumns.DISPLAY_NAME to "orphan.jpg"))
        try {
            MediaRowMapper.map(row, ContentCategory.IMAGES, "external_primary")
            fail("Expected RowMappingException")
        } catch (e: RowMappingException) {
            assertTrue(e.message!!.contains("_ID"))
        }
    }

    @Test
    fun `screenshot hint is computed for images only`() {
        val screenshotRow = imageRow(id = 1, name = "Screenshot_20250911-141234.png", mimeType = "image/png")
        val image = MediaRowMapper.map(screenshotRow, ContentCategory.IMAGES, "external_primary")
        assertTrue(image.isScreenshot == true)

        val video = MediaRowMapper.map(imageRow(id = 2, name = "Screenshot_20250911-141234.png"), ContentCategory.VIDEOS, "external_primary")
        assertNull(video.screenshotScore)
        assertNull(video.isScreenshot)
    }
}