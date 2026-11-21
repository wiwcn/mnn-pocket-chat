package ai.mnn.mnn_pocket_chat

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import ai.mnn.pocket.MnnLlmBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MnnLlmBridge(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext.filesDir.absolutePath,
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOWNLOADS_CHANNEL,
        ).setMethodCallHandler { call, result -> handleDownloadCall(call, result) }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> {
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
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val mime = call.argument<String>("mimeType") ?: "text/plain"
                    if (path == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            file,
                        )
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = mime
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(send, "分享调试日志"))
                        result.success(true)
                    } catch (_: Throwable) {
                        result.success(false)
                    }
                }
                "readNativeTrace" -> {
                    // native 层同步落盘的 trace（含崩溃堆栈），供调试页展示/导出。
                    try {
                        val f = File(applicationContext.filesDir, "native_trace.log")
                        result.success(if (f.exists()) f.readText() else "")
                    } catch (_: Throwable) {
                        result.success("")
                    }
                }
                "clearNativeTrace" -> {
                    try {
                        val f = File(applicationContext.filesDir, "native_trace.log")
                        if (f.exists()) f.writeText("")
                        result.success(true)
                    } catch (_: Throwable) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
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
