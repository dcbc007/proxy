package com.aurumproxy.aurum_proxy

import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "aurum_proxy/vpn_permission"
        private const val VPN_PERMISSION_REQUEST_CODE = 42420
    }

    private var pendingVpnPermissionResult: MethodChannel.Result? = null
    private var vpnDialogLaunched = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "check" -> result.success(VpnService.prepare(this) == null)
                "request" -> requestVpnPermission(result)
                "version" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success(info.versionName ?: "")
                }
                "filesDir" -> {
                    val dir = getExternalFilesDir(null) ?: filesDir
                    result.success(dir.absolutePath)
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

        if (pendingVpnPermissionResult != null) {
            // Do not wedge the Flutter side if an OEM failed to deliver
            // the previous activity result. Continue to the native plugin,
            // which performs its own authoritative VpnService.prepare() check.
            result.success(true)
            return
        }

        pendingVpnPermissionResult = result
        vpnDialogLaunched = true

        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, VPN_PERMISSION_REQUEST_CODE)
        } catch (e: Exception) {
            vpnDialogLaunched = false
            pendingVpnPermissionResult = null
            result.error("VPN_DIALOG_FAILED", e.message, null)
        }
    }

    private fun finishVpnDialogRequest() {
        if (!vpnDialogLaunched) return
        vpnDialogLaunched = false
        val pending = pendingVpnPermissionResult
        pendingVpnPermissionResult = null
        // Some OEM Android builds report RESULT_CANCELED even after the user
        // confirms the VPN dialog. Treat "dialog closed" as permission-flow
        // completion and let v2ray_box perform the real VpnService.prepare()
        // check before starting the service.
        pending?.success(true)
    }

    override fun onResume() {
        super.onResume()
        if (vpnDialogLaunched && pendingVpnPermissionResult != null) {
            Handler(Looper.getMainLooper()).postDelayed({
                if (vpnDialogLaunched && pendingVpnPermissionResult != null) {
                    finishVpnDialogRequest()
                }
            }, 350)
        }
    }

    @Deprecated("Deprecated in Android SDK; kept for FlutterActivity compatibility.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST_CODE) {
            finishVpnDialogRequest()
        }
    }
}
