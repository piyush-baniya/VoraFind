package com.piyushbaniya.vorafind.content

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts

/** A SAF document-tree grant as reported across the bridge. */
data class DocumentGrant(
    val uri: String,
    val displayName: String,
    val persisted: Boolean,
    val readable: Boolean,
    val writable: Boolean,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "uri" to uri,
        "displayName" to displayName,
        "persisted" to persisted,
        "readable" to readable,
        "writable" to writable,
    )
}

internal fun Uri.isTreeUri(): Boolean = path?.contains("/tree/") == true

/**
 * SAF plumbing: pick a folder, persist read access, list and release grants.
 *
 * Grant persistence is owned by Android (persistable URI permissions). VoraFind
 * only reports the grant; the future database layer may persist it as metadata.
 */
class DocumentAccessService(private val activity: ComponentActivity) {

    private var pendingPicker: ((Uri?) -> Unit)? = null

    private val pickerLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        val picked = result.data?.data
        pendingPicker?.invoke(picked)
        pendingPicker = null
    }

    private val resolver
        get() = activity.contentResolver

    /**
     * Launches [Intent.ACTION_OPEN_DOCUMENT_TREE]. [onPicked] receives null when the
     * user cancels; picker unavailability is reported through [onUnavailable].
     */
    fun requestTree(
        onPicked: (Uri?) -> Unit,
        onUnavailable: (code: String, message: String?) -> Unit,
    ) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        )
        pendingPicker = onPicked
        try {
            pickerLauncher.launch(intent)
        } catch (e: Exception) {
            pendingPicker = null
            onUnavailable("pickUnavailable", e.javaClass.simpleName)
        }
    }

    /** Records the read grant and turns a picked tree URI into [DocumentGrant] metadata. */
    fun grantInfo(treeUri: Uri): DocumentGrant {
        val persisted = try {
            resolver.takePersistableUriPermission(treeUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            true
        } catch (_: Exception) {
            false
        }
        return DocumentGrant(
            uri = treeUri.toString(),
            displayName = displayNameFor(treeUri),
            persisted = persisted,
            readable = true,
            writable = false,
        )
    }

    /** Currently effective persisted tree grants (externally revoked grants drop out automatically). */
    fun persistedGrants(): List<DocumentGrant> =
        resolver.persistedUriPermissions
            .filter { it.isReadPermission && it.uri.isTreeUri() }
            .map { permission ->
                DocumentGrant(
                    uri = permission.uri.toString(),
                    displayName = displayNameFor(permission.uri),
                    persisted = true,
                    readable = permission.isReadPermission,
                    writable = permission.isWritePermission,
                )
            }
            .sortedBy { it.displayName }

    fun hasTreeGrant(): Boolean =
        resolver.persistedUriPermissions.any { it.isReadPermission && it.uri.isTreeUri() }

    /** Releases the persisted read grant. Returns false when nothing was released. */
    fun release(uriString: String): Boolean {
        val uri = try {
            Uri.parse(uriString)
        } catch (_: Exception) {
            return false
        }
        return try {
            resolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun displayNameFor(treeUri: Uri): String {
        val fromProvider = try {
            val documentId = DocumentsContract.getTreeDocumentId(treeUri)
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
            resolver.query(
                documentUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
        if (!fromProvider.isNullOrBlank()) return fromProvider
        val fromPath = treeUri.lastPathSegment?.substringAfterLast(':')?.takeIf { it.isNotBlank() }
        return fromPath ?: FALLBACK_DISPLAY_NAME
    }

    private companion object {
        const val FALLBACK_DISPLAY_NAME = "Document tree"
    }
}