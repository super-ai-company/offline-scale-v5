package com.vdamov3.cashier_trae

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Only user-requested official updates. Never runs during checkout/startup. */
class UpdateChannel(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    @Suppress("DEPRECATION")
    private fun current() = activity.packageManager.getPackageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES)
    @Suppress("DEPRECATION")
    private fun signatures(info: android.content.pm.PackageInfo): Set<String> {
        val certs = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return certs?.map { MessageDigest.getInstance("SHA-256").digest(it.toByteArray()).joinToString("") { b -> "%02x".format(b) } }?.toSet() ?: emptySet()
    }
    @Suppress("DEPRECATION")
    private fun versionCode(info: android.content.pm.PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "version") { result.success(current().versionName); return }
        if (call.method != "install") { result.notImplemented(); return }
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
            result.success(false); return
        }
        val url = call.argument<String>("url") ?: ""
        val version = call.argument<String>("version") ?: ""
        val expected = call.argument<String>("sha256") ?: ""
        val size = call.argument<Number>("size")?.toLong() ?: 0L
        val official = "https://github.com/super-ai-company/offline-scale-v5/releases/download/v$version/offline-scale-android-v$version.apk"
        if (!version.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+")) || url != official || !expected.matches(Regex("[a-f0-9]{64}")) || size <= 0 || size > 250L * 1024 * 1024) {
            result.error("invalid", "Invalid update metadata", null); return
        }
        if (!busy.compareAndSet(false, true)) { result.error("busy", "Update in progress", null); return }
        executor.execute {
            val folder = File(activity.cacheDir, "app-updates").apply { mkdirs() }
            val partial = File(folder, "update.part")
            val apk = File(folder, "update.apk")
            try {
                var target = URL(url)
                var response: HttpsURLConnection? = null
                for (attempt in 0..5) {
                    require(target.protocol == "https" && target.host in setOf("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"))
                    val connection = target.openConnection() as HttpsURLConnection
                    connection.connectTimeout = 15000; connection.readTimeout = 30000; connection.instanceFollowRedirects = false
                    val code = connection.responseCode
                    if (code in listOf(301,302,303,307,308)) {
                        val next = connection.getHeaderField("Location") ?: error("Missing redirect")
                        connection.disconnect(); target = URL(target, next)
                    } else {
                        require(code == 200); response = connection; break
                    }
                }
                val connection = response ?: error("Too many redirects")
                val digest = MessageDigest.getInstance("SHA-256")
                var count = 0L
                val started = System.nanoTime()
                try {
                    connection.inputStream.use { input -> partial.outputStream().use { output ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            if (Thread.currentThread().isInterrupted || System.nanoTime() - started > 600_000_000_000L) error("Download cancelled")
                            val n = input.read(buffer); if (n < 0) break
                            count += n; require(count <= size)
                            digest.update(buffer,0,n); output.write(buffer,0,n)
                        }
                    } }
                } finally { connection.disconnect() }
                require(count == size && digest.digest().joinToString("") { "%02x".format(it) } == expected)
                @Suppress("DEPRECATION")
                val archive = activity.packageManager.getPackageArchiveInfo(partial.path, PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES) ?: error("Invalid APK")
                val installed = current()
                require(archive.packageName == activity.packageName && archive.versionName == version && versionCode(archive) > versionCode(installed))
                require(signatures(installed).isNotEmpty() && signatures(archive) == signatures(installed))
                if (apk.exists()) require(apk.delete())
                require(partial.renameTo(apk))
                activity.runOnUiThread {
                    try {
                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
                        activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result.success(true)
                    } catch (_: Exception) { result.error("install", "Cannot open installer", null) }
                    finally { busy.set(false) }
                }
            } catch (_: Exception) {
                partial.delete(); busy.set(false)
                activity.runOnUiThread { result.error("update", "Update could not be verified or downloaded", null) }
            }
        }
    }
    fun close() { executor.shutdownNow() }
}
