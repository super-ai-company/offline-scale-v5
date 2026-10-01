package com.vdamov3.cashier_trae

import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Store distribution has no APK downloader or installer. */
class UpdateChannel(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "distribution" -> result.success("play")
            "version" -> result.success(activity.packageManager.getPackageInfo(activity.packageName, 0).versionName)
            "openStore" -> {
                try {
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=${activity.packageName}")))
                    result.success(true)
                } catch (_: Exception) { result.success(false) }
            }
            "install" -> result.error("store_only", "Updates are managed by Google Play", null)
            else -> result.notImplemented()
        }
    }
    fun close() {}
}
