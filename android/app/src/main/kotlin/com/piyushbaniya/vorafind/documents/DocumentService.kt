package com.piyushbaniya.vorafind.documents

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import java.io.FileNotFoundException
import java.io.IOException
import java.util.ArrayDeque
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class DocumentException(val code: String, message: String) : Exception(message)

class DocumentService(
    private val context: Context,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "vorafind-documents").apply { isDaemon = true }
    },
) {

    fun enumerateTree(
        treeUriString: String,
        maxDepth: Int = 8,
        maxItems: Int = 5000,
        onResult: (Result<DocumentEnumerationWireResult>) -> Unit,
    ) {
        executor.execute {
            try {
                val result = runEnumerateTree(treeUriString, maxDepth, maxItems)
                onResult(Result.success(result))
            } catch (e: DocumentException) {
                onResult(Result.failure(e))
            } catch (e: SecurityException) {
                onResult(Result.success(DocumentEnumerationWireResult(emptyList(), inaccessible = true, truncated = false)))
            } catch (e: Exception) {
                onResult(Result.failure(DocumentException(DocumentError.UNKNOWN, e.message ?: "Enumeration failed")))
            }
        }
    }

    fun extractText(
        contentUriString: String,
        mimeType: String?,
        maxChars: Int = 200000,
        onResult: (Result<DocumentExtractionWireResult>) -> Unit,
    ) {
        executor.execute {
            try {
                val result = runExtractText(contentUriString, mimeType, maxChars)
                onResult(Result.success(result))
            } catch (e: DocumentException) {
                onResult(Result.failure(e))
            } catch (e: SecurityException) {
                onResult(Result.failure(DocumentException(DocumentError.INACCESSIBLE, "Access denied to content URI")))
            } catch (e: FileNotFoundException) {
                onResult(Result.failure(DocumentException(DocumentError.URI_UNAVAILABLE, "Document not found at content URI")))
            } catch (e: Exception) {
                onResult(Result.failure(DocumentException(DocumentError.PARSE_FAILED, e.message ?: "Extraction failed")))
            }
        }
    }

    private fun runEnumerateTree(
        treeUriString: String,
        maxDepth: Int,
        maxItems: Int,
    ): DocumentEnumerationWireResult {
        val treeUri = try {
            Uri.parse(treeUriString)
        } catch (_: Exception) {
            throw DocumentException(DocumentError.INVALID_ARGUMENTS, "Invalid tree URI")
        }

        val rootDocId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (_: Exception) {
            return DocumentEnumerationWireResult(emptyList(), inaccessible = true, truncated = false)
        }

        val records = mutableListOf<DocumentWireRecord>()
        var truncated = false

        // BFS traversal: (documentId, currentDepth, parentRelativePath)
        val queue = ArrayDeque<Triple<String, Int, String?>>()
        queue.add(Triple(rootDocId, 0, null))

        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )

        val resolver = context.contentResolver

        while (queue.isNotEmpty() && !truncated) {
            val (parentDocId, currentDepth, parentPath) = queue.removeFirst()
            val childrenUri = try {
                DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
            } catch (_: Exception) {
                continue
            }

            try {
                resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val docId = cursor.getString(0) ?: continue
                        val displayName = cursor.getString(1) ?: "Untitled"
                        val mime = cursor.getString(2)
                        val size = if (cursor.isNull(3)) null else cursor.getLong(3)
                        val modifiedMillis = if (cursor.isNull(4)) null else cursor.getLong(4)
                        val modifiedSeconds = modifiedMillis?.let { it / 1000 }

                        val relativePath = if (parentPath == null) displayName else "$parentPath/$displayName"

                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                            if (currentDepth + 1 < maxDepth) {
                                queue.add(Triple(docId, currentDepth + 1, relativePath))
                            }
                        } else {
                            val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId).toString()
                            val stableKey = DocumentWireRecord.buildStableKey(treeUriString, docId)
                            records.add(
                                DocumentWireRecord(
                                    stableKey = stableKey,
                                    treeUri = treeUriString,
                                    documentId = docId,
                                    uri = docUri,
                                    displayName = displayName,
                                    mimeType = mime,
                                    sizeBytes = size,
                                    dateModified = modifiedSeconds,
                                    relativePath = relativePath,
                                )
                            )
                            if (records.size >= maxItems) {
                                truncated = true
                                break
                            }
                        }
                    }
                }
            } catch (e: SecurityException) {
                return DocumentEnumerationWireResult(emptyList(), inaccessible = true, truncated = false)
            } catch (_: Exception) {
                // Individual folder query failure does not abort the entire enumeration
            }
        }

        return DocumentEnumerationWireResult(
            documents = records,
            inaccessible = false,
            truncated = truncated,
        )
    }

    private fun runExtractText(
        contentUriString: String,
        mimeType: String?,
        maxChars: Int,
    ): DocumentExtractionWireResult {
        val uri = try {
            Uri.parse(contentUriString)
        } catch (_: Exception) {
            throw DocumentException(DocumentError.INVALID_ARGUMENTS, "Invalid content URI")
        }

        val effectiveMime = mimeType ?: context.contentResolver.getType(uri) ?: ""

        val isPdf = effectiveMime.equals("application/pdf", ignoreCase = true) ||
            uri.lastPathSegment?.endsWith(".pdf", ignoreCase = true) == true

        val isText = effectiveMime.startsWith("text/", ignoreCase = true) ||
            effectiveMime.equals("application/json", ignoreCase = true)

        if (!isPdf && !isText) {
            throw DocumentException(DocumentError.UNSUPPORTED_TYPE, "Unsupported document type: $effectiveMime")
        }

        val inputStream = context.contentResolver.openInputStream(uri)
            ?: throw DocumentException(DocumentError.URI_UNAVAILABLE, "Unable to open content stream")

        return if (isPdf) {
            extractPdfText(inputStream, maxChars)
        } else {
            extractPlainText(inputStream, maxChars)
        }
    }

    private fun extractPdfText(
        inputStream: java.io.InputStream,
        maxChars: Int,
    ): DocumentExtractionWireResult {
        var doc: PDDocument? = null
        try {
            doc = PDDocument.load(inputStream)
            if (doc.isEncrypted) {
                throw DocumentException(DocumentError.ENCRYPTED, "PDF is password protected.")
            }
            val stripper = PDFTextStripper()
            val text = stripper.getText(doc) ?: ""
            val isTruncated = text.length > maxChars
            val boundedText = if (isTruncated) text.substring(0, maxChars) else text
            return DocumentExtractionWireResult(
                text = boundedText,
                truncated = isTruncated,
            )
        } catch (e: DocumentException) {
            throw e
        } catch (e: Exception) {
            throw DocumentException(DocumentError.PARSE_FAILED, e.message ?: "Failed to parse PDF document")
        } finally {
            try {
                doc?.close()
            } catch (_: Exception) {}
            try {
                inputStream.close()
            } catch (_: Exception) {}
        }
    }

    private fun extractPlainText(
        inputStream: java.io.InputStream,
        maxChars: Int,
    ): DocumentExtractionWireResult {
        try {
            val reader = inputStream.bufferedReader(Charsets.UTF_8)
            val buffer = CharArray(4096)
            val sb = StringBuilder()
            var isTruncated = false
            var read: Int
            while (reader.read(buffer).also { read = it } != -1) {
                if (sb.length + read >= maxChars) {
                    val remaining = maxChars - sb.length
                    if (remaining > 0) {
                        sb.append(buffer, 0, remaining)
                    }
                    isTruncated = true
                    break
                }
                sb.append(buffer, 0, read)
            }
            return DocumentExtractionWireResult(
                text = sb.toString(),
                truncated = isTruncated,
            )
        } catch (e: Exception) {
            throw DocumentException(DocumentError.PARSE_FAILED, e.message ?: "Failed to read text document")
        } finally {
            try {
                inputStream.close()
            } catch (_: Exception) {}
        }
    }
}
