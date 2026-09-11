package com.piyushbaniya.vorafind.ocr

import androidx.activity.ComponentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart <-> Kotlin OCR surface (architecture: "small, typed, documented").
 *
 * MethodChannel `vorafind/ocr`:
 *
 *  - `recognizeText(contentUri, maxWidth?)` -> success `{text}` or failure
 *    `{errorCode, errorMessage}`. Error codes are stable strings from
 *    [OcrError]; the Dart facade maps them back into `OcrErrorCode`.
 *
 * Heavy lifting lives in [OcrService]; this class only validates arguments and
 * forwards the (possibly busy-rejected) result back to Dart.
 */
class OcrBridge(private val activity: ComponentActivity) : MethodChannel.MethodCallHandler {

    private val service = OcrService(loader = OcrBitmapLoader(activity.applicationContext))

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognizeText" -> {
                val contentUri = call.argument<String>("contentUri")
                if (contentUri.isNullOrBlank()) {
                    result.error(
                        OcrError.INVALID_ARGUMENTS,
                        "A content URI is required.",
                        null,
                    )
                    return
                }
                val maxWidth = call.argument<Number>("maxWidth")?.toInt()
                service.recognizeText(contentUri, maxWidth) { outcome ->
                    if (outcome.errorCode == null) {
                        result.success(outcome.toMap())
                    } else {
                        result.error(outcome.errorCode, outcome.errorMessage, null)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL_NAME = "vorafind/ocr"
    }
}