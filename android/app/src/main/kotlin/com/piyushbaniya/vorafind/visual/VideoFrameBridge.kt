package com.piyushbaniya.vorafind.visual

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.roundToInt

class VideoFrameBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(this)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "sampleFrames") { result.notImplemented(); return }
        val contentUri = call.argument<String>("contentUri")
        if (contentUri.isNullOrBlank()) {
            result.error("invalidArguments", "A content URI is required.", null); return
        }
        val maxFrames = (call.argument<Number>("maxFrames")?.toInt() ?: 12).coerceIn(1, 12)
        val dimension = (call.argument<Number>("dimension")?.toInt() ?: 224).coerceIn(64, 224)
        Thread({
            try { result.success(sample(contentUri, maxFrames, dimension)) }
            catch (e: VideoSampleException) { result.error(e.code, e.message, null) }
            catch (_: SecurityException) { result.error("denied", "Denied.", null) }
            catch (e: Exception) { result.error("corrupt", e.message, null) }
            // An Error (e.g. OutOfMemoryError on a high-resolution source) must
            // never kill the process or leave the Dart future hanging: route it
            // back as a controlled failure (Prompt #15.1).
            catch (e: Throwable) { result.error("failed", e.message ?: "Frame sampling failed.", null) }
        }, "vorafind-video").apply { isDaemon = true }.start()
    }
    private fun sample(uri: String, maxF: Int, dim: Int): Map<String, Any?> {
        val parsed = try { Uri.parse(uri) } catch (_: Exception) { null }
            ?: throw VideoSampleException("invalidArguments", "Bad URI.")
        val ret = MediaMetadataRetriever()
        try {
            try { ret.setDataSource(context, parsed) }
            catch (_: SecurityException) { throw VideoSampleException("denied", "Denied.") }
            catch (_: Exception) { throw VideoSampleException("corrupt", "Open failed.") }
            val dur = ret.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            val count = if (dur == null || dur <= 0) 4.coerceAtMost(maxF)
                else if (dur < 10000) 4.coerceAtMost(maxF).coerceAtLeast(1)
                else if (dur < 60000) 8.coerceAtMost(maxF).coerceAtLeast(1)
                else maxF
            if (count <= 0) throw VideoSampleException("unsupported", "No duration.")
            val durUs = (dur ?: 30000) * 1000L
            val start = (durUs * 0.05).toLong()
            val end = (durUs * 0.95).toLong()
            val frames = ArrayList<Map<String, Any?>>(count)
            for (slot in 0 until count) {
                val ts = if (count == 1) start else start + (end - start) / max(count - 1, 1) * slot
                // getScaledFrameAtTime (API 27+) decodes a downscaled frame
                // directly, avoiding a full-resolution bitmap for 4K sources
                // (the number one OOM crash during indexing, Prompt #15.1).
                val bmp = try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        ret.getScaledFrameAtTime(ts, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, dim, dim)
                    } else {
                        ret.getFrameAtTime(ts, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    }
                } catch (_: Exception) { null } ?: continue
                try {
                    val small = scaleCrop(bmp, dim)
                    frames.add(mapOf("tsMs" to ts / 1000, "rgb" to rgb(small)))
                    if (!bmp.isRecycled) bmp.recycle()
                } catch (_: Exception) { if (!bmp.isRecycled) bmp.recycle() }
            }
            if (frames.isEmpty()) throw VideoSampleException("corrupt", "No frames.")
            return mapOf("durationMs" to dur, "frames" to frames)
        } finally { try { ret.release() } catch (_: Exception) {} }
    }
    private fun scaleCrop(src: Bitmap, dim: Int): Bitmap {
        val sc = max(dim.toFloat() / src.width, dim.toFloat() / src.height)
        val sw = (src.width * sc).roundToInt().coerceAtLeast(1)
        val sh = (src.height * sc).roundToInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(src, sw, sh, true)
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
        val w = b.width; val h = b.height
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
    companion object { const val CHANNEL_NAME = "vorafind/video" }
}

private class VideoSampleException(val code: String, message: String) : Exception(message)
