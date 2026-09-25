package com.helpmebrands.reward

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The device's IANA zone for push registration; Dart only sees an
        // abbreviation such as "BST".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.helpmebrands.reward/timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "current") {
                    result.success(TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }
    }
}
