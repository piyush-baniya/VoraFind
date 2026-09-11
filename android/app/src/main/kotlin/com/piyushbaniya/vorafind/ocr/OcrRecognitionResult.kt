package com.piyushbaniya.vorafind.ocr

/**
 * Wire-level result of one `recognizeText` call, shared with the Dart side.
 *
 * Success carries [text] and a null error; failure carries a stable [errorCode]
 * (see [OcrError]) plus a human-readable message. These names are part of the
 * Dart <-> Kotlin contract: keep them in sync with `OcrErrorCode.fromWire` in
 * `lib/core/ocr/ocr_models.dart`.
 */
data class OcrRecognitionResult(
    val text: String? = null,
    val errorCode: String? = null,
    val errorMessage: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "text" to text,
        "errorCode" to errorCode,
        "errorMessage" to errorMessage,
    )

    companion object {
        fun success(text: String) = OcrRecognitionResult(text = text)

        fun failure(code: String, message: String) =
            OcrRecognitionResult(errorCode = code, errorMessage = message)
    }
}

/** Stable error codes crossing the `vorafind/ocr` channel. */
object OcrError {
    const val INVALID_ARGUMENTS = "invalidArguments"
    const val BUSY = "busy"
    const val URI_UNAVAILABLE = "uriUnavailable"
    const val DECODE_FAILED = "decodeFailed"
    const val OCR_FAILED = "ocrFailed"
}