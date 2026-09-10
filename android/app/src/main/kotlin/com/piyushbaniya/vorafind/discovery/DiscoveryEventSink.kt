package com.piyushbaniya.vorafind.discovery

import io.flutter.plugin.common.EventChannel

/**
 * Outbound discovery events. `send` is only ever called from the discovery
 * engine's single background thread (single-writer invariant).
 */
fun interface DiscoveryEventSink {
    fun send(event: Map<String, Any?>)
}

/** Adapter to Flutter's [EventChannel.EventSink]; every event is a success value. */
class FlutterEventSinkAdapter(private val sink: EventChannel.EventSink) : DiscoveryEventSink {
    override fun send(event: Map<String, Any?>) = sink.success(event)
}

/** No-op sink used before Flutter attaches; keeps the engine total. */
object NoopDiscoveryEventSink : DiscoveryEventSink {
    override fun send(event: Map<String, Any?>) = Unit
}