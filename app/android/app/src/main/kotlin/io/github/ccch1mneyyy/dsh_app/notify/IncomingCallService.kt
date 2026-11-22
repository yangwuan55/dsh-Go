package io.github.ccch1mneyyy.dsh_app.notify

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import io.github.ccch1mneyyy.dsh_app.runtime.DshService

/** Keeps Dart (and with it every host connection) alive while the incoming-call switch is on. */
class IncomingCallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Upgrades still carry the old channel: drop it so settings don't show a dead 来电保活 row.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java)?.deleteNotificationChannel(LEGACY_KEEP_CHANNEL)
        }
        try {
            // The keep-alive stays a foreground service, but publishes the engine's notification:
            // one DSH Go row instead of a second one carrying no more information.
            val notification = DshService.foregroundNotification(this)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(DshService.NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                @Suppress("DEPRECATION")
                startForeground(DshService.NOTIFICATION_ID, notification)
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
        // Our notification ID is shared with the engine; put the engine's row back when we stop.
        DshService.updateNotification(this)
        super.onDestroy()
    }

    companion object {
        private const val LEGACY_KEEP_CHANNEL = "dsh-incoming-call-keep"
        const val EXTRA_TITLE = "title"
        const val EXTRA_SESSION = "sessionId"

        @Volatile var running = false
            private set

        /** Repost the shared row after the engine drops it, without restarting this service. */
        internal fun repost(context: Context) {
            if (!running) return
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            nm.notify(DshService.NOTIFICATION_ID, DshService.foregroundNotification(context))
        }

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
    }
}
