package com.llmshell.llmshell

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class SshSessionForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val count = intent?.getIntExtra(EXTRA_COUNT, 1) ?: 1
                startForeground(NOTIFICATION_ID, buildNotification(count))
            }
        }
        return START_STICKY
    }

    private fun buildNotification(sessionCount: Int): Notification {
        createChannel()
        val openApp = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val label = if (sessionCount == 1) "1 SSH session active" else "$sessionCount SSH sessions active"
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("llmshell")
            .setContentText(label)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SSH sessions",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps SSH connections alive while the app is in the background."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "ssh_session"
        const val NOTIFICATION_ID = 1001
        const val EXTRA_COUNT = "count"
        const val ACTION_STOP = "com.llmshell.llmshell.STOP_FOREGROUND"
    }
}
