package com.piyushbaniya.vorafind

import android.os.Bundle
import com.piyushbaniya.vorafind.content.ContentAccessBridge
import com.piyushbaniya.vorafind.discovery.DiscoveryBridge
import com.piyushbaniya.vorafind.documents.DocumentBridge
import com.piyushbaniya.vorafind.ocr.OcrBridge
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PDFBoxResourceLoader.init(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ContentAccessBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
        DiscoveryBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
        OcrBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
        DocumentBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}