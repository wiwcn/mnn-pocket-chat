package ai.mnn.mnn_pocket_chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/** Keeps model downloads alive while the app is in the background. */
class DownloadForegroundService : Service() {

    private var text: String = ""
    private var progress: Int = -1
    private var foregrounded = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                text = intent.getStringExtra(EXTRA_TEXT) ?: ""
                progress = intent.getIntExtra(EXTRA_PROGRESS, -1)
                startForegroundCompat(buildNotification())
            }

            ACTION_UPDATE -> {
                // 服务未在前台时忽略更新，避免误触发前台服务启动。
                if (!foregrounded) return START_NOT_STICKY
                intent.getStringExtra(EXTRA_TEXT)?.let { text = it }
                if (intent.hasExtra(EXTRA_PROGRESS)) {
                    progress = intent.getIntExtra(EXTRA_PROGRESS, progress)
                }
                startForegroundCompat(buildNotification())
            }

            ACTION_STOP -> {
                if (foregrounded) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    foregrounded = false
                }
                stopSelf()
                return START_NOT_STICKY
            }

            else -> return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foregrounded = true
    }

    private fun buildNotification(): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(NOTIFICATION_TITLE)
            .setContentText(text.ifEmpty { NOTIFICATION_TITLE })
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (progress < 0) {
            builder.setProgress(0, 0, true)
        } else {
            builder.setProgress(100, progress.coerceIn(0, 100), false)
        }
        return builder.build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "START"
        const val ACTION_UPDATE = "UPDATE"
        const val ACTION_STOP = "STOP"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress"

        const val CHANNEL_ID = "downloads"
        const val CHANNEL_NAME = "模型下载"
        const val NOTIFICATION_TITLE = "模型下载"
        const val NOTIFICATION_ID = 2301

        @Volatile
        var isRunning: Boolean = false
            private set
    }
}
