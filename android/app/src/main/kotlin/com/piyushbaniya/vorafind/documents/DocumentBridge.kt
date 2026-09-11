package com.piyushbaniya.vorafind.documents

import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DocumentBridge(
    activity: ComponentActivity,
    private val service: DocumentService = DocumentService(activity.applicationContext),
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enumerateDocumentTree" -> {
                val treeUri = call.argument<String>("treeUri")
                if (treeUri.isNullOrBlank()) {
                    result.error(DocumentError.INVALID_ARGUMENTS, "treeUri is required", null)
                    return
                }
                val maxDepth = call.argument<Number>("maxDepth")?.toInt() ?: 8
                val maxItems = call.argument<Number>("maxItems")?.toInt() ?: 5000

                service.enumerateTree(treeUri, maxDepth, maxItems) { outcome ->
                    mainHandler.post {
                        outcome.fold(
                            onSuccess = { result.success(it.toMap()) },
                            onFailure = { error ->
                                if (error is DocumentException) {
                                    result.error(error.code, error.message, null)
                                } else {
                                    result.error(DocumentError.UNKNOWN, error.message, null)
                                }
                            },
                        )
                    }
                }
            }

            "extractDocumentText" -> {
                val contentUri = call.argument<String>("contentUri")
                if (contentUri.isNullOrBlank()) {
                    result.error(DocumentError.INVALID_ARGUMENTS, "contentUri is required", null)
                    return
                }
                val mimeType = call.argument<String>("mimeType")
                val maxChars = call.argument<Number>("maxChars")?.toInt() ?: 200000

                service.extractText(contentUri, mimeType, maxChars) { outcome ->
                    mainHandler.post {
                        outcome.fold(
                            onSuccess = { result.success(it.toMap()) },
                            onFailure = { error ->
                                if (error is DocumentException) {
                                    result.error(error.code, error.message, null)
                                } else {
                                    result.error(DocumentError.UNKNOWN, error.message, null)
                                }
                            },
                        )
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL_NAME = "vorafind/documents"
    }
}
