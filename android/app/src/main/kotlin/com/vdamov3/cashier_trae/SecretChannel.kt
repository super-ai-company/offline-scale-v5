package com.vdamov3.cashier_trae

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** UKEY is encrypted at rest with a non-exportable Android Keystore key. */
class SecretChannel(context: Context) : MethodChannel.MethodCallHandler {
    private val prefs = context.getSharedPreferences("printer_secrets", Context.MODE_PRIVATE)
    private val alias = "offline_cashier_feie_v1"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
        }.generateKey()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "readFeieKey" -> {
                    val encoded = prefs.getString("ukey", null)
                    if (encoded == null) { result.success(""); return }
                    val parts = encoded.split(":")
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128,
                        Base64.decode(parts[0], Base64.NO_WRAP)))
                    result.success(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                }
                "writeFeieKey" -> {
                    val value = call.arguments as? String ?: error("Invalid key")
                    require(value.isNotBlank() && value.length <= 256)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, key())
                    val data = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                        Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
                    check(prefs.edit().putString("ukey", data).commit())
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("SECRET_STORAGE", "Unable to access encrypted printer key", null)
        }
    }
}
