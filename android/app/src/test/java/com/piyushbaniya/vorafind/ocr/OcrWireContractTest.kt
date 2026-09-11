package com.piyushbaniya.vorafind.ocr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Keeps the Kotlin `vorafind/ocr` wire contract in sync with the Dart facade
 * (`OcrErrorCode.fromWire`, `OcrDetector.recognizeText`) so a renamed error code
 * or result key fails a test instead of silently mapping to `unknown`.
 */
class OcrWireContractTest {

    @Test
    fun `error codes match the Dart OcrErrorCode names`() {
        // Names after "enum OcrErrorCode {" in lib/core/ocr/ocr_models.dart.
        val dartNames = setOf(
            "uriUnavailable",
            "decodeFailed",
            "ocrFailed",
            "busy",
            "invalidArguments",
        )
        val kotlinCodes = setOf(
            OcrError.URI_UNAVAILABLE,
            OcrError.DECODE_FAILED,
            OcrError.OCR_FAILED,
            OcrError.BUSY,
            OcrError.INVALID_ARGUMENTS,
        )
        assertEquals(dartNames, kotlinCodes)
    }

    @Test
    fun `success payload exposes only text`() {
        val result = OcrRecognitionResult.success("hello world")
        assertEquals("hello world", result.text)
        assertNull(result.errorCode)
        assertNull(result.errorMessage)
    }

    @Test
    fun `failure payload exposes a stable code and message`() {
        val result = OcrRecognitionResult.failure(OcrError.DECODE_FAILED, "boom")
        assertNull(result.text)
        assertEquals(OcrError.DECODE_FAILED, result.errorCode)
        assertEquals("boom", result.errorMessage)
    }

    @Test
    fun `mapping to the Dart map keeps the agreed keys`() {
        val success = OcrRecognitionResult.success("x").toMap()
        assertEquals(listOf("text", "errorCode", "errorMessage"), success.keys.toList())
        assertEquals("x", success["text"])
        val failure = OcrRecognitionResult.failure(OcrError.BUSY, "busy now").toMap()
        assertEquals(OcrError.BUSY, failure["errorCode"])
        assertNull(failure["text"])
    }
}