package com.vdamov3.cashier_trae

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val weightChannel = WeightChannel()
    private val printChannel by lazy { PrintChannel(applicationContext) }
    private val aiChannel by lazy { AiEmbeddingChannel(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 称重 MethodChannel
        MethodChannel(messenger, "cashier/weight").setMethodCallHandler(weightChannel)
        // 称重数据 EventChannel（实时推送重量）
        EventChannel(messenger, "cashier/weight/events").setStreamHandler(weightChannel)

        // 打印 MethodChannel
        MethodChannel(messenger, "cashier/print").setMethodCallHandler(printChannel)
        MethodChannel(messenger, "cashier/secrets").setMethodCallHandler(SecretChannel(applicationContext))
        MethodChannel(messenger, "cashier/ai_embedding").setMethodCallHandler(aiChannel)
    }

    override fun onDestroy() {
        super.onDestroy()
        // 关闭串口，释放资源
        weightChannel.shutdown()
        printChannel.shutdown()
        aiChannel.close()
    }
}
