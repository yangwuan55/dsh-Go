package io.github.ccch1mneyyy.dsh_app.notify

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
import android.util.Log
import io.github.ccch1mneyyy.dsh_app.R
import io.github.ccch1mneyyy.dsh_app.i18n.AppStrings

/** Keeps Dart (and with it every host connection) alive while the incoming-call switch is on. */
class IncomingCallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        channels(this)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(KEEP_ID, keepNotification(this), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                @Suppress("DEPRECATION")
                startForeground(KEEP_ID, keepNotification(this))
            }
            running = true
        } catch (e: Exception) {
            Log.w("DshIncomingCall", "foreground start refused", e)
            running = false
            stopSelf(startId)
        }
        return if (running) START_STICKY else START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val KEEP_CHANNEL = "dsh-incoming-call-keep"
        private const val KEEP_ID = 3091
        const val EXTRA_TITLE = "title"
        const val EXTRA_SESSION = "sessionId"

        @Volatile var running = false
            private set

        fun ensure(context: Context, on: Boolean): Boolean {
            if (on == running) return running
            val app = context.applicationContext
            try {
                if (on) {
                    app.startForegroundService(Intent(app, IncomingCallService::class.java))
                    running = true
                } else {
                    app.stopService(Intent(app, IncomingCallService::class.java))
                    running = false
                }
                return true
            } catch (e: Exception) {
                Log.w("DshIncomingCall", "service ${if (on) "start" else "stop"} refused", e)
                running = false
                return false
            }
        }

        private fun channels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(KEEP_CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(KEEP_CHANNEL, AppStrings.get(context, R.string.incoming_call_keep_channel), NotificationManager.IMPORTANCE_MIN).apply {
                        setSound(null, null)
                        enableVibration(false)
                        setShowBadge(false)
                    },
                )
            }
        }

        private fun keepNotification(context: Context): Notification =
            Notification.Builder(AppStrings.context(context), KEEP_CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_dsh)
                .setContentTitle(AppStrings.get(context, R.string.incoming_call_keep_channel))
                .setContentIntent(
                    PendingIntent.getActivity(
                        context, KEEP_ID,
                        Intent(context, io.github.ccch1mneyyy.dsh_app.MainActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    ),
                )
                .setOngoing(true)
                .build()
    }
}
