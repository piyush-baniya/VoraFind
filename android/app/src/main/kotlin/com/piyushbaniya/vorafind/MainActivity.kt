package com.piyushbaniya.vorafind

import com.piyushbaniya.vorafind.content.ContentAccessBridge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ContentAccessBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}