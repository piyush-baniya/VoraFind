package com.piyushbaniya.vorafind.ocr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface

/** Outcome of trying to turn a content URI into a decodable bitmap. */
sealed class OcrDecodeResult {
    /** The URI could not be opened at all (gone, or permission revoked). */
    data object Unavailable : OcrDecodeResult()

    /** Bytes were readable but do not form a decodable image. */
    data object Undecodable : OcrDecodeResult()

    data class Decoded(val bitmap: Bitmap) : OcrDecodeResult()
}

/**
 * Loads a sampled, EXIF-rotated bitmap for OCR without ever decoding the full
 * sensor resolution: a bounds-only pass picks the downsample factor, then the
 * image is decoded with that factor and rotated according to its orientation
 * metadata (portrait phone photos would otherwise yield rotated text).
 */
class OcrBitmapLoader(private val context: Context) {

    fun load(uri: Uri, maxDimension: Int): OcrDecodeResult {
        val bounds = boundsOf(uri)
        if (bounds == null) return OcrDecodeResult.Unavailable
        val (width, height) = bounds
        if (width <= 0 || height <= 0) return OcrDecodeResult.Undecodable

        val sampleSize = ImageSampler.inSampleSizeFor(width, height, maxDimension)
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val decoded = try {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, options)
            }
        } catch (_: Exception) {
            null
        }
        if (decoded == null) return OcrDecodeResult.Undecodable
        return OcrDecodeResult.Decoded(rotateToOrientation(decoded, uri))
    }

    private fun boundsOf(uri: Uri): Pair<Int, Int>? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        return try {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, options)
                Pair(options.outWidth, options.outHeight)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun rotateToOrientation(bitmap: Bitmap, uri: Uri): Bitmap {
        val orientation = readOrientation(uri)
        if (orientation == null ||
            orientation == ExifInterface.ORIENTATION_NORMAL ||
            orientation == ExifInterface.ORIENTATION_UNDEFINED
        ) {
            return bitmap
        }
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
        }
        val rotated = try {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (_: Exception) {
            return bitmap
        }
        bitmap.recycle()
        return rotated
    }

    private fun readOrientation(uri: Uri): Int? = try {
        context.contentResolver.openInputStream(uri)?.use { input ->
            ExifInterface(input).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        }
    } catch (_: Exception) {
        null
    }
}