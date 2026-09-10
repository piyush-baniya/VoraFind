package com.piyushbaniya.vorafind.discovery

import androidx.activity.ComponentActivity
import com.piyushbaniya.vorafind.content.ContentCategory
import com.piyushbaniya.vorafind.content.MediaPermissionService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart <-> Kotlin discovery surface (architecture §13):
 *
 *  - MethodChannel `vorafind/indexing`  — commands (start, ack, cancel, status)
 *  - EventChannel  `vorafind/indexing/events` — typed discovery events
 *
 * Keeps the command surface small; all heavy lifting lives in [DiscoveryEngine].
 */
class DiscoveryBridge(private val activity: ComponentActivity) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val mediaPermissionService = MediaPermissionService(activity)
    private val engine = DiscoveryEngine(
        querier = MediaStoreQuerier(activity.applicationContext),
        accessFor = { category -> mediaPermissionService.stateFor(category) },
    )

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL_NAME).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL_NAME).setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startDiscovery" -> {
                val categories = parseCategories(call.argument<List<String>>("categories"))
                if (categories == null) {
                    result.error("invalidArguments", "A non-empty category list is required.", null)
                    return
                }
                try {
                    result.success(engine.start(DiscoveryOptions(categories)).toMap())
                } catch (e: Exception) {
                    result.error("discoveryStartFailed", "Could not start discovery.", null)
                }
            }

            "ackBatch" -> {
                val sequence = call.argument<Number>("sequence")?.toInt()
                if (sequence == null) {
                    result.error("invalidArguments", "A batch sequence is required.", null)
                    return
                }
                result.success(engine.ackBatch(sequence))
            }

            "cancelDiscovery" -> result.success(engine.cancel())

            "getDiscoveryStatus" -> result.success(engine.status().toMap())

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        engine.attachSink(FlutterEventSinkAdapter(events))
    }

    override fun onCancel(arguments: Any?) {
        engine.attachSink(null)
    }

    private fun parseCategories(raw: List<String>?): List<ContentCategory>? {
        if (raw.isNullOrEmpty()) return null
        return try {
            raw.map { ContentCategory.fromWire(it) }
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    companion object {
        const val METHOD_CHANNEL_NAME = "vorafind/indexing"
        const val EVENT_CHANNEL_NAME = "vorafind/indexing/events"
    }
}