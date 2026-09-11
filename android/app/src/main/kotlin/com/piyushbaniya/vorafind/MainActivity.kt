package com.piyushbaniya.vorafind

import com.piyushbaniya.vorafind.content.ContentAccessBridge
import com.piyushbaniya.vorafind.discovery.DiscoveryBridge
import com.piyushbaniya.vorafind.ocr.OcrBridge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ContentAccessBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
        DiscoveryBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
        OcrBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}