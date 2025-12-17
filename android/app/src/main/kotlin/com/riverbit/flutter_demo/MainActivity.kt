package com.riverbit.flutter_demo

import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.riverbit.flutter_demo/wallet"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "launchMetaMask") {
                val uri = call.argument<String>("uri")
                if (uri != null) {
                    val success = launchMetaMaskApp(uri)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "URI is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun launchMetaMaskApp(uri: String): Boolean {
        return try {
            // 方法1: 尝试使用 metamask:// 协议
            val metamaskUri = "metamask://wc?uri=${Uri.encode(uri)}"
            val intent1 = Intent(Intent.ACTION_VIEW, Uri.parse(metamaskUri))
            intent1.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent1)
                Log.d("MainActivity", "Launched MetaMask with metamask:// protocol")
                return true
            } catch (e: Exception) {
                Log.d("MainActivity", "Failed to launch with metamask://: ${e.message}")
            }

            // 方法2: 尝试使用 walletconnect:// 协议
            val walletConnectUri = uri.replace("wc:", "walletconnect:")
            val intent2 = Intent(Intent.ACTION_VIEW, Uri.parse(walletConnectUri))
            intent2.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent2)
                Log.d("MainActivity", "Launched MetaMask with walletconnect:// protocol")
                return true
            } catch (e: Exception) {
                Log.d("MainActivity", "Failed to launch with walletconnect://: ${e.message}")
            }

            // 方法3: 尝试直接启动 MetaMask 应用包
            val intent3 = packageManager.getLaunchIntentForPackage("io.metamask")
            if (intent3 != null) {
                intent3.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                intent3.putExtra("wc_uri", uri)
                startActivity(intent3)
                Log.d("MainActivity", "Launched MetaMask app directly")
                return true
            } else {
                Log.d("MainActivity", "MetaMask app not found")
                false
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error launching MetaMask: ${e.message}")
            false
        }
    }
}
