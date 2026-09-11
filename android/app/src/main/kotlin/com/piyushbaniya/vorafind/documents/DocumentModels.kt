package com.piyushbaniya.vorafind.documents

import java.net.URLEncoder

object DocumentError {
    const val URI_UNAVAILABLE = "uriUnavailable"
    const val TOO_LARGE = "tooLarge"
    const val ENCRYPTED = "encrypted"
    const val PARSE_FAILED = "parseFailed"
    const val UNSUPPORTED_TYPE = "unsupportedType"
    const val BUSY = "busy"
    const val INVALID_ARGUMENTS = "invalidArguments"
    const val INACCESSIBLE = "inaccessible"
    const val PLATFORM_UNAVAILABLE = "platformUnavailable"
    const val UNKNOWN = "unknown"
}

data class DocumentWireRecord(
    val stableKey: String,
    val treeUri: String,
    val documentId: String,
    val uri: String,
    val displayName: String,
    val mimeType: String?,
    val sizeBytes: Long?,
    val dateModified: Long?,
    val relativePath: String?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "stableKey" to stableKey,
        "treeUri" to treeUri,
        "documentId" to documentId,
        "uri" to uri,
        "displayName" to displayName,
        "mimeType" to mimeType,
        "sizeBytes" to sizeBytes,
        "dateModified" to dateModified,
        "relativePath" to relativePath,
    )

    companion object {
        fun buildStableKey(treeUri: String, documentId: String): String {
            val encodedTree = URLEncoder.encode(treeUri, "UTF-8")
            val encodedDoc = URLEncoder.encode(documentId, "UTF-8")
            return "saf:$encodedTree:$encodedDoc"
        }
    }
}

data class DocumentEnumerationWireResult(
    val documents: List<DocumentWireRecord>,
    val inaccessible: Boolean,
    val truncated: Boolean,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "documents" to documents.map { it.toMap() },
        "inaccessible" to inaccessible,
        "truncated" to truncated,
    )
}

data class DocumentExtractionWireResult(
    val text: String,
    val truncated: Boolean,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "text" to text,
        "truncated" to truncated,
    )
}
