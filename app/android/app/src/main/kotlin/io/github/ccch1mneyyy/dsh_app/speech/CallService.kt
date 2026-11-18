package io.github.ccch1mneyyy.dsh_app.speech

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.github.ccch1mneyyy.dsh_app.MainActivity
import io.github.ccch1mneyyy.dsh_app.R
import io.github.ccch1mneyyy.dsh_app.i18n.AppStrings

/**
 * Keeps a voice call's microphone and playback alive while the app is in the background or the
 * screen is locked. Android mutes the microphone of a backgrounded app, so the call runs as a
 * microphone-type foreground service for as long as it lasts; the ongoing notification is the way
 * back to the call. The partial wake lock keeps the CPU up while the screen is off.
 *
 * Started from [SpeechPlugin.startCall] and stopped from its endCall (which also runs when the
 * call fails or the engine detaches). No call state or transcript goes into the notification.
 */
class CallService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // A stop may have arrived before this start was delivered (a call that failed at once).
        if (!wanted) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        ensureChannel()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                @Suppress("DEPRECATION")
                startForeground(NOTIFICATION_ID, notification())
            }
        } catch (_: Exception) {
            // Without the foreground notification Android would cut the microphone in the background.
            stopSelf(startId)
            return START_NOT_STICKY
        }
        acquireWakeLock()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dsh-app:speech-call").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, AppStrings.get(this, R.string.speech_call_channel), NotificationManager.IMPORTANCE_LOW).apply {
                description = AppStrings.get(this, R.string.speech_call_channel_description)
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
    }

    private fun notification(): Notification {
        val ctx = AppStrings.context(this)
        // Tap the notification to bring the call page back; it is still the top route of MainActivity.
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_dsh)
            .setContentTitle(AppStrings.get(ctx, R.string.speech_call_notification_title))
            .setContentText(AppStrings.get(ctx, R.string.speech_call_notification_text))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "dsh-speech-call"
        private const val NOTIFICATION_ID = 3084
        private val main = Handler(Looper.getMainLooper())

        /** Cleared before the stop is posted: a start delivered later would show a stale call. */
        @Volatile private var wanted = false
        @Volatile private var instance: CallService? = null
        @Volatile private var generation = 0

        /** False when Android refused to start the service; then the call cannot go to the background. */
        fun start(context: Context): Boolean {
            wanted = true
            generation++
            val app = context.applicationContext
            if (runCatching { app.startForegroundService(Intent(app, CallService::class.java)) }.isSuccess) return true
            wanted = false
            return false
        }

        fun stop() {
            val mine = generation
            wanted = false
            main.post { if (generation == mine) instance?.stopSelf() }
        }
    }
}
