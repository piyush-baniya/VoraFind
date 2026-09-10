package com.piyushbaniya.vorafind.content

import android.Manifest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MediaRequestPolicyTest {

    @Test
    fun `Android 13+ uses per-category media permissions`() {
        assertArrayEquals(
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES),
            permissionsFor(ContentCategory.IMAGES, 33),
        )
        assertArrayEquals(
            arrayOf(Manifest.permission.READ_MEDIA_VIDEO),
            permissionsFor(ContentCategory.VIDEOS, 34),
        )
        assertArrayEquals(
            arrayOf(Manifest.permission.READ_MEDIA_AUDIO),
            permissionsFor(ContentCategory.AUDIO, 35),
        )
    }

    @Test
    fun `Android 12 and below share one external storage permission`() {
        for (category in listOf(
            ContentCategory.IMAGES,
            ContentCategory.VIDEOS,
            ContentCategory.AUDIO,
        )) {
            assertArrayEquals(
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                permissionsFor(category, 32),
            )
            assertArrayEquals(
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                permissionsFor(category, 24),
            )
        }
    }

    @Test
    fun `documents never map to a media permission`() {
        assertThrows(IllegalArgumentException::class.java) {
            permissionsFor(ContentCategory.DOCUMENTS, 34)
        }
    }
}