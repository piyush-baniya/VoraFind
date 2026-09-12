package com.piyushbaniya.vorafind.ocr

import android.net.Uri
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Runs one recognition request on a dedicated single daemon thread using the
 * local ML Kit text recognizer (bundled model — no network involved). Off-device
 * results stay on the device (privacy rules §8).
 *
 * Invariants:
 *  - at most one recognition is in flight at a time (single-flight guard);
 *    a concurrent request is rejected with `busy`, never queued indefinitely;
 *  - each run creates and closes its own [TextRecognizer] (close after use per
 *    ML Kit guidance), so a failed run cannot poison later ones.
 */
class OcrService(
    private val loader: OcrBitmapLoader,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "vorafind-ocr").apply { isDaemon = true }
    },
) {
    private val inFlight = AtomicBoolean(false)

    /**
     * Invokes [onResult] exactly once, on the worker thread, with the result of
     * recognizing [contentUri]. Returns immediately; never blocks the caller.
     */
    fun recognizeText(
        contentUri: String,
        maxDimension: Int?,
        onResult: (OcrRecognitionResult) -> Unit,
    ) {
        if (!inFlight.compareAndSet(false, true)) {
            onResult(
                OcrRecognitionResult.failure(
                    OcrError.BUSY,
                    "A recognition call is still in flight.",
                ),
            )
            return
        }
        executor.execute {
            // onResult is invoked exactly once regardless of what happens in
            // runRecognize. In particular an Error (e.g. OutOfMemoryError while
            // decoding) must not kill the process nor leave the Dart side
            // waiting for a result that never arrives (Prompt #15.1).
            val result = try {
                runRecognize(contentUri, maxDimension)
            } catch (_: Throwable) {
                OcrRecognitionResult.failure(
                    OcrError.OCR_FAILED,
                    "The text recognizer failed.",
                )
            }
            try {
                onResult(result)
            } finally {
                inFlight.set(false)
            }
        }
    }

    private fun runRecognize(contentUri: String, maxDimension: Int?): OcrRecognitionResult {
        val uri = try {
            Uri.parse(contentUri)
        } catch (_: Exception) {
            return OcrRecognitionResult.failure(
                OcrError.INVALID_ARGUMENTS,
                "The content URI is malformed.",
            )
        }
        if (uri.scheme != "content") {
            return OcrRecognitionResult.failure(
                OcrError.INVALID_ARGUMENTS,
                "Only content:// URIs are supported.",
            )
        }
        return when (val decoded = loader.load(uri, maxDimension ?: ImageSampler.DEFAULT_MAX_DIMENSION)) {
            is OcrDecodeResult.Unavailable -> OcrRecognitionResult.failure(
                OcrError.URI_UNAVAILABLE,
                "The content URI could not be opened.",
            )

            is OcrDecodeResult.Undecodable -> OcrRecognitionResult.failure(
                OcrError.DECODE_FAILED,
                "The image could not be decoded.",
            )

            is OcrDecodeResult.Decoded -> recognize(decoded.bitmap)
        }
    }

    private fun recognize(bitmap: android.graphics.Bitmap): OcrRecognitionResult {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            val image = InputImage.fromBitmap(bitmap, 0)
            val visionText = Tasks.await(recognizer.process(image))
            return OcrRecognitionResult.success(visionText.text)
        } catch (_: Exception) {
            return OcrRecognitionResult.failure(
                OcrError.OCR_FAILED,
                "The text recognizer failed.",
            )
        } finally {
            recognizer.close()
            bitmap.recycle()
        }
    }
}