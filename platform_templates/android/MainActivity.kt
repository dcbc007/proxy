package com.aurumproxy.aurum_proxy

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "aurum_proxy/vpn_permission"
        private const val VPN_PERMISSION_REQUEST_CODE = 42420
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "check" -> {
                    result.success(VpnService.prepare(this) == null)
                }

                "request" -> {
                    requestVpnPermission(result)
                }

                "version" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success(info.versionName ?: "")
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = try {
            VpnService.prepare(this)
        } catch (e: Exception) {
            result.error("VPN_PREPARE_FAILED", e.message, null)
            return
        }

        if (intent == null) {
            result.success(true)
            return
        }

        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, VPN_PERMISSION_REQUEST_CODE)
            // Return immediately. Dart polls VpnService.prepare() until Android
            // has committed the user's decision. This avoids OEM/activity-result
            // timing issues that can leave the connection flow suspended.
            result.success(true)
        } catch (e: Exception) {
            result.error("VPN_DIALOG_FAILED", e.message, null)
        }
    }

    @Deprecated("Deprecated in Android SDK; kept for FlutterActivity compatibility.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
    }
}
