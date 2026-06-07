package com.llmshell.llmshell

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.llmshell.llmshell/foreground",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val count = call.argument<Int>("count") ?: 1
                    val intent = Intent(this, SshSessionForegroundService::class.java).apply {
                        putExtra(SshSessionForegroundService.EXTRA_COUNT, count)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(this, SshSessionForegroundService::class.java).apply {
                        action = SshSessionForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
