package com.piyushbaniya.vorafind.content

import androidx.activity.ComponentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handles the Dart -> Kotlin `vorafind/content_access` method channel.
 *
 * Keeps [MainActivity] free of permission/SAF logic. Discovery will later use a
 * separate `vorafind/indexing` channel (architecture §13), so this surface stays
 * small: capabilities, permission state/request, SAF tree grants.
 */
class ContentAccessBridge(private val activity: ComponentActivity) : MethodChannel.MethodCallHandler {

    private val mediaPermissionService = MediaPermissionService(activity)
    private val documentAccessService = DocumentAccessService(activity)
    private val capabilityService =
        ContentCapabilityService(activity, mediaPermissionService, documentAccessService)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(capabilityService.capabilities())

            "getPermissionState" -> {
                val category = categoryArgument(call, result) ?: return
                val state = stateFor(category)
                if (state == null) {
                    result.error("invalidArguments", "Cannot resolve permission state.", null)
                    return
                }
                result.success(category.accessMap(state))
            }

            "requestMediaAccess" -> {
                val category = categoryArgument(call, result) ?: return
                if (category == ContentCategory.DOCUMENTS) {
                    result.error(
                        "invalidArguments",
                        "Documents are granted through the folder picker, not a permission request.",
                        null,
                    )
                    return
                }
                try {
                    mediaPermissionService.request(category) { state ->
                        result.success(category.accessMap(state))
                    }
                } catch (e: Exception) {
                    result.error(
                        "permissionRequestFailed",
                        "Could not start the permission request.",
                        null,
                    )
                }
            }

            "requestDocumentTree" -> {
                documentAccessService.requestTree(
                    onPicked = { treeUri ->
                        if (treeUri == null) {
                            result.success(mapOf("cancelled" to true, "grant" to null))
                        } else {
                            result.success(
                                mapOf(
                                    "cancelled" to false,
                                    "grant" to documentAccessService.grantInfo(treeUri).toMap(),
                                ),
                            )
                        }
                    },
                    onUnavailable = { code, message -> result.error(code, message, null) },
                )
            }

            "listDocumentTreeGrants" ->
                result.success(documentAccessService.persistedGrants().map { it.toMap() })

            "releaseDocumentTreeGrant" -> {
                val uri = call.argument<String>("uri")
                if (uri.isNullOrBlank()) {
                    result.error("invalidArguments", "A document-tree URI is required.", null)
                    return
                }
                result.success(documentAccessService.release(uri))
            }

            else -> result.notImplemented()
        }
    }

    private fun stateFor(category: ContentCategory): ContentAccessState? = when (category) {
        ContentCategory.DOCUMENTS ->
            if (documentAccessService.hasTreeGrant()) {
                ContentAccessState.PARTIAL_ACCESS
            } else {
                ContentAccessState.NO_ACCESS
            }
        else -> try {
            mediaPermissionService.stateFor(category)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun categoryArgument(call: MethodCall, result: MethodChannel.Result): ContentCategory? =
        try {
            ContentCategory.fromWire(call.argument<String>("category") ?: "")
        } catch (_: IllegalArgumentException) {
            result.error("invalidArguments", "Unknown content category.", null)
            null
        }

    companion object {
        const val CHANNEL_NAME = "vorafind/content_access"
    }
}