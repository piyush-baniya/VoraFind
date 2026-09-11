package com.piyushbaniya.vorafind.documents

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentWireContractTest {

    @Test
    fun `error codes match the Dart DocumentErrorCode wire names`() {
        val expectedCodes = setOf(
            "uriUnavailable",
            "tooLarge",
            "encrypted",
            "parseFailed",
            "unsupportedType",
            "busy",
            "invalidArguments",
            "inaccessible",
            "platformUnavailable",
            "unknown",
        )
        val kotlinCodes = setOf(
            DocumentError.URI_UNAVAILABLE,
            DocumentError.TOO_LARGE,
            DocumentError.ENCRYPTED,
            DocumentError.PARSE_FAILED,
            DocumentError.UNSUPPORTED_TYPE,
            DocumentError.BUSY,
            DocumentError.INVALID_ARGUMENTS,
            DocumentError.INACCESSIBLE,
            DocumentError.PLATFORM_UNAVAILABLE,
            DocumentError.UNKNOWN,
        )
        assertEquals(expectedCodes, kotlinCodes)
    }

    @Test
    fun `stable key encodes tree uri and document id safely`() {
        val tree = "content://com.android.externalstorage.documents/tree/primary%3ADocuments"
        val docId = "primary:Documents/test space.pdf"
        val key = DocumentWireRecord.buildStableKey(tree, docId)
        assertTrue(key.startsWith("saf:"))
        assertTrue(key.contains("test+space.pdf") || key.contains("test%20space.pdf"))
    }

    @Test
    fun `enumeration result wire mapping has agreed shape`() {
        val record = DocumentWireRecord(
            stableKey = "saf:tree:doc1",
            treeUri = "content://tree",
            documentId = "doc1",
            uri = "content://tree/document/doc1",
            displayName = "Report.pdf",
            mimeType = "application/pdf",
            sizeBytes = 1024L,
            dateModified = 1700000000L,
            relativePath = "Work/Report.pdf",
        )
        val result = DocumentEnumerationWireResult(
            documents = listOf(record),
            inaccessible = false,
            truncated = false,
        )
        val map = result.toMap()
        assertEquals(false, map["inaccessible"])
        assertEquals(false, map["truncated"])
        val docs = map["documents"] as List<*>
        assertEquals(1, docs.size)
        val docMap = docs[0] as Map<*, *>
        assertEquals("saf:tree:doc1", docMap["stableKey"])
        assertEquals("Report.pdf", docMap["displayName"])
        assertEquals("Work/Report.pdf", docMap["relativePath"])
    }

    @Test
    fun `extraction result wire mapping has agreed shape`() {
        val result = DocumentExtractionWireResult(
            text = "Extracted invoice text",
            truncated = false,
        )
        val map = result.toMap()
        assertEquals("Extracted invoice text", map["text"])
        assertEquals(false, map["truncated"])
    }
}
