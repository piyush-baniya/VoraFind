package com.piyushbaniya.vorafind.visual

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.piyushbaniya.vorafind.ocr.OcrBitmapLoader
import com.piyushbaniya.vorafind.ocr.OcrDecodeResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Native Android endpoints for image-pixel access and image similarity
 * (docs/similar-image-search.md, §Platform bridge).
 *
 * Serves three methods on `vorafind/image`:
 *
 * * `readImageRgb` — decodes a content URI to an exact `dimension×dimension`
 *   RGB888 sample for the embedding model. Reuses the OCR loader's bounded,
 *   EXIF-aware decode (`OcrBitmapLoader` + `ImageSampler`) so portrait phone
 *   photos embed as seen and no full-sensor bitmap is ever allocated.
 * * `readImagePng` — a bounded square PNG preview of any content URI, for the
 *   similar-images screen (`Image.memory`).
 * * `pickImage` — the system image picker ([Intent.ACTION_GET_CONTENT]). No
 *   storage permission is needed; the app only ever receives a content URI.
 *
 * All decoding runs off the UI thread (daemon threads, mirroring
 * [VideoFrameBridge]); a corrupt/denied image is a stable error code, never a
 * crash. Image bytes stay on-device (privacy rules §8).
 */
class ImageVisualBridge(private val activity: ComponentActivity) :
    MethodChannel.MethodCallHandler {

    private val context: Context get() = activity.applicationContext

    // Single-flight picker: exactly one system pick may be in flight.
    private var pendingPick: MethodChannel.Result? = null
    private val picker = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result: ActivityResult ->
        val pending = pendingPick ?: return@registerForActivityResult
        pendingPick = null
        if (result.resultCode != Activity.RESULT_OK) {
            pending.error("cancelled", "No image chosen.", null)
            return@registerForActivityResult
        }
        val data = result.data
        val uri = data?.data
        if (uri == null) {
            pending.error("cancelled", "No image chosen.", null)
            return@registerForActivityResult
        }
        // ACTION_GET_CONTENT returns a (usually transient) read grant; take a
        // persistable one when the system offers it so the preview/embedding
        // stay readable after the granting activity is gone. Best-effort: a
        // transient grant suffices for the current session.
        if (data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0) {
            try {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: Exception) {
                // Transient grant is fine — swallow.
            }
        }
        pending.success(mapOf("uri" to uri.toString()))
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readImageRgb" -> readImageRgb(call, result)
            "readImagePng" -> readImagePng(call, result)
            "pickImage" -> pickImage(result)
            else -> result.notImplemented()
        }
    }

    private fun pickImage(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("failed", "A pick is already in progress.", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
        }
        picker.launch(intent)
    }

    private fun readImageRgb(call: MethodCall, result: MethodChannel.Result) {
        val contentUri = call.argument<String>("contentUri")
        if (contentUri.isNullOrBlank()) {
            result.error("invalidContentUri", "A content URI is required.", null)
            return
        }
        val dimension = (call.argument<Number>("dimension")?.toInt() ?: 224).coerceIn(64, 224)
        Thread({
            try {
                val bmp = decode(contentUri, dimension)
                val small = scaleCrop(bmp, dimension)
                val rgb = rgb(small)
                result.success(mapOf("width" to small.width, "height" to small.height, "rgb" to rgb))
            } catch (e: ImageVisualException) {
                result.error(e.code, e.message, null)
            } catch (_: SecurityException) {
                result.error("denied", "Denied.", null)
            } catch (e: Throwable) {
                result.error("failed", e.message ?: "Image decode failed.", null)
            }
        }, "vorafind-image").apply { isDaemon = true }.start()
    }

    private fun readImagePng(call: MethodCall, result: MethodChannel.Result) {
        val contentUri = call.argument<String>("contentUri")
        if (contentUri.isNullOrBlank()) {
            result.error("invalidContentUri", "A content URI is required.", null)
            return
        }
        val maxDimension = (call.argument<Number>("maxDimension")?.toInt() ?: 384).coerceIn(128, 1024)
        Thread({
            try {
                val bmp = decode(contentUri, maxDimension)
                val square = scaleCrop(bmp, maxDimension)
                val out = ByteArrayOutputStream()
                square.compress(Bitmap.CompressFormat.PNG, 100, out)
                square.recycle()
                result.success(mapOf("bytes" to out.toByteArray()))
            } catch (e: ImageVisualException) {
                result.error(e.code, e.message, null)
            } catch (_: SecurityException) {
                result.error("denied", "Denied.", null)
            } catch (e: Throwable) {
                result.error("failed", e.message ?: "Image decode failed.", null)
            }
        }, "vorafind-image").apply { isDaemon = true }.start()
    }

    /** Bounds-pass, EXIF-aware decode (same pipeline as OCR, Prompt #8). */
    private fun decode(contentUri: String, maxDimension: Int): Bitmap {
        val parsed = try {
            Uri.parse(contentUri)
        } catch (_: Exception) {
            throw ImageVisualException("invalidContentUri", "Bad URI.")
        }
        return when (val decoded = OcrBitmapLoader(context).load(parsed, maxDimension)) {
            is OcrDecodeResult.Unavailable ->
                throw ImageVisualException("denied", "Unavailable.")
            is OcrDecodeResult.Undecodable ->
                throw ImageVisualException("corrupt", "Undecodable image.")
            is OcrDecodeResult.Decoded -> decoded.bitmap
        }
    }

    /** Scale-to-fit then center-crop to an exact square (identical to the video
     * frame sampler's geometry; kept private here so the shipped video sampler
     * is not touched). */
    private fun scaleCrop(src: Bitmap, dim: Int): Bitmap {
        val sc = max(dim.toFloat() / src.width, dim.toFloat() / src.height)
        val sw = (src.width * sc).roundToInt().coerceAtLeast(1)
        val sh = (src.height * sc).roundToInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(src, sw, sh, true)
        if (scaled != src) src.recycle()
        val x = ((sw - dim) / 2).coerceAtLeast(0)
        val y = ((sh - dim) / 2).coerceAtLeast(0)
        val crop = Bitmap.createBitmap(scaled, x, y, dim.coerceAtMost(sw), dim.coerceAtMost(sh))
        if (crop.width != dim || crop.height != dim) {
            val exact = Bitmap.createScaledBitmap(crop, dim, dim, true)
            if (scaled != src) scaled.recycle()
            if (crop != exact) crop.recycle()
            return exact
        }
        if (scaled != crop && scaled != src) scaled.recycle()
        return crop
    }

    private fun rgb(b: Bitmap): ByteArray {
        val w = b.width
        val h = b.height
        val px = IntArray(w * h)
        b.getPixels(px, 0, w, 0, 0, w, h)
        val buf = ByteBuffer.allocate(w * h * 3)
        for (p in px) {
            buf.put(((p shr 16) and 0xFF).toByte())
            buf.put(((p shr 8) and 0xFF).toByte())
            buf.put((p and 0xFF).toByte())
        }
        b.recycle()
        return buf.array()
    }

    companion object {
        const val CHANNEL_NAME = "vorafind/image"
    }
}

private class ImageVisualException(val code: String, message: String) : Exception(message)