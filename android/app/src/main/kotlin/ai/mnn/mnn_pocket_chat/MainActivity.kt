package ai.mnn.mnn_pocket_chat

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import ai.mnn.pocket.MnnLlmBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MnnLlmBridge(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOWNLOADS_CHANNEL,
        ).setMethodCallHandler { call, result -> handleDownloadCall(call, result) }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "openUrl") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url == null || !url.startsWith("https://")) {
                result.success(false)
                return@setMethodCallHandler
            }
            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                result.success(true)
            } catch (_: Throwable) {
                result.success(false)
            }
        }
    }

    private fun handleDownloadCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ensurePermission" -> {
                ensureNotificationPermission()
                // 不阻塞下载：无论用户是否授权都立即返回。
                result.success(true)
            }

            "start" -> {
                val title = call.argument<String>("title") ?: "模型下载"
                val text = call.argument<String>("text") ?: "准备中…"
                val progress = call.argument<Int>("progress") ?: -1
                try {
                    val intent = Intent(this, DownloadForegroundService::class.java)
                        .setAction(DownloadForegroundService.ACTION_START)
                        .putExtra(DownloadForegroundService.EXTRA_TITLE, title)
                        .putExtra(DownloadForegroundService.EXTRA_TEXT, text)
                        .putExtra(DownloadForegroundService.EXTRA_PROGRESS, progress)
                    ContextCompat.startForegroundService(this, intent)
                } catch (_: Throwable) {
                    // 后台能力不可用时忽略，不影响下载。
                }
                result.success(null)
            }

            "update" -> {
                val text = call.argument<String>("text")
                val progress = call.argument<Int>("progress")
                if (!DownloadForegroundService.isRunning) {
                    result.success(false)
                    return
                }
                try {
                    val intent = Intent(this, DownloadForegroundService::class.java)
                        .setAction(DownloadForegroundService.ACTION_UPDATE)
                    if (text != null) {
                        intent.putExtra(DownloadForegroundService.EXTRA_TEXT, text)
                    }
                    if (progress != null) {
                        intent.putExtra(DownloadForegroundService.EXTRA_PROGRESS, progress)
                    }
                    startService(intent)
                } catch (_: Throwable) {
                    // 服务已停止或系统限制时忽略。
                }
                result.success(null)
            }

            "stop" -> {
                if (DownloadForegroundService.isRunning) {
                    try {
                        val intent = Intent(this, DownloadForegroundService::class.java)
                            .setAction(DownloadForegroundService.ACTION_STOP)
                        startService(intent)
                    } catch (_: Throwable) {
                        // 忽略停止失败。
                    }
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    companion object {
        private const val DOWNLOADS_CHANNEL = "pocket_chat/downloads"
        private const val SYSTEM_CHANNEL = "pocket_chat/system"
        private const val REQUEST_POST_NOTIFICATIONS = 4301
    }
}
