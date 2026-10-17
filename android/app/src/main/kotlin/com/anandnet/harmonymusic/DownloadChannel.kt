package com.anandnet.harmonymusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * "riff/downloads": while songs or episodes download, a foreground service
 * ([DownloadService]) keeps Riff running and its notification shows how
 * far they've got (lib/services/download_notice.dart), as YouTube Music's
 * and AntennaPod's downloads do. Android freezes an app a while after it
 * leaves the screen, and a download stopped there unless music played.
 * Needs no activity, like riff/network: downloads go on with the screen
 * off.
 */
object DownloadChannel : MethodChannel.MethodCallHandler {
    /** Set by MainActivity. */
    var appContext: Context? = null

    const val NOTIFICATION_ID = 7302
    private const val CHANNEL_ID = "riff_downloads"

    // What the notification says now.
    private var title = ""
    private var text = ""
    private var done = 0
    private var total = 0
    private var channelName = "Downloads"

    /** Dart wants it shown (false after "stop"). */
    var wanted = false

    /** Asked to start, not in the foreground yet. */
    var starting = false

    /** In the foreground, its notification up. */
    var inForeground = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.success(false)
            return
        }
        when (call.method) {
            "show" -> {
                title = call.argument<String>("title") ?: ""
                text = call.argument<String>("text") ?: ""
                done = call.argument<Int>("done") ?: 0
                total = call.argument<Int>("total") ?: 0
                channelName = call.argument<String>("channel") ?: channelName
                wanted = true
                result.success(show(context))
            }
            "stop" -> {
                wanted = false
                // Still starting: it stops itself once in the foreground (it
                // has to get there first, or Android ends the app).
                if (inForeground) {
                    context.stopService(Intent(context, DownloadService::class.java))
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun show(context: Context): Boolean {
        if (inForeground) {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager)
                ?.notify(NOTIFICATION_ID, notification(context))
            return true
        }
        if (starting) return true
        return try {
            val intent = Intent(context, DownloadService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            starting = true
            true
        } catch (_: Exception) {
            // Not allowed now (Android 12+ won't start one from the
            // background): the downloads go on as before.
            false
        }
    }

    fun notification(context: Context): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        channelName,
                        NotificationManager.IMPORTANCE_LOW
                    )
                )
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    context,
                    0,
                    it,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_riff)
            .setContentTitle(title)
            .setContentText(text)
            .setProgress(total, done, total <= 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .build()
    }
}

/** The foreground service behind [DownloadChannel]. */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = DownloadChannel.notification(this)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    DownloadChannel.NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(DownloadChannel.NOTIFICATION_ID, notification)
            }
            DownloadChannel.inForeground = true
        } catch (_: Exception) {
            DownloadChannel.wanted = false
        }
        DownloadChannel.starting = false
        // Stopped (or done) while it was starting.
        if (!DownloadChannel.wanted) stopSelf()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        DownloadChannel.inForeground = false
        DownloadChannel.starting = false
        super.onDestroy()
    }
}
