package io.github.ccch1mneyyy.dsh_app.notify

import android.app.ActivityOptions
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import io.github.ccch1mneyyy.dsh_app.R
import io.github.ccch1mneyyy.dsh_app.i18n.AppStrings

/** Self-managed Telecom call: Telecom routes audio and keeps the lock-screen call alive; our page draws the UI. */
class DshConnectionService : ConnectionService() {
    override fun onCreate() {
        super.onCreate()
        register(this)
    }

    override fun onCreateIncomingConnection(
        account: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ): Connection {
        val extras = request?.extras ?: Bundle.EMPTY
        val title = extras.getString(IncomingCallService.EXTRA_TITLE).orEmpty()
        val sessionId = extras.getString(IncomingCallService.EXTRA_SESSION).orEmpty()
        settled = false
        val connection = object : Connection() {
            private var ended = false

            override fun onAnswer(videoState: Int) {
                if (settled || active !== this) return
                settled = true
                stopRinging()
                signal("answer")
                setActive()
            }

            override fun onDisconnect() {
                if (ended) return
                ended = true
                // A stale call must still leave Telecom, or its audio mode never comes back.
                if (active === this) {
                    settled = true
                    cancelCallPage()
                    signal("hangup")
                    active = null
                    stopRinging()
                }
                setDisconnected(DisconnectCause(DisconnectCause.REMOTE))
                destroy()
            }

            override fun onAbort() {
                onDisconnect()
            }
        }
        active = connection
        connection.setAddress(Uri.parse("dsh:$sessionId"), TelecomManager.PRESENTATION_ALLOWED)
        connection.setCallerDisplayName(title, TelecomManager.PRESENTATION_ALLOWED)
        connection.setAudioModeIsVoip(true)
        connection.setRinging()
        // Self-managed calls never get a system ringtone: we own the sound and the vibration.
        startRinging(applicationContext)
        // A service's startActivity is a blocked background launch; our PendingIntent
        // carries the creator's opt-in (set in showCallPage), so sending it raises the page.
        showCallPage(applicationContext, title, sessionId)?.send()
        return connection
    }

    override fun onCreateIncomingConnectionFailed(account: PhoneAccountHandle?, request: ConnectionRequest?) {
        if (!settled) {
            settled = true
            cancelCallPage()
            signal("hangup")
        }
    }

    companion object {
        private const val TAG = "DshIncomingCall"
        private const val ACCOUNT_ID = "dsh-incoming"
        private const val PAGE_CHANNEL = "dsh-incoming-page-v2"
        private const val PAGE_ID = 3092
        @Volatile private var active: Connection? = null
        @Volatile private var settled = false
        @Volatile private var appContext: Context? = null
        @Volatile private var ringtone: Ringtone? = null
        @Volatile private var vibrator: Vibrator? = null

        private fun startRinging(context: Context) {
            stopRinging()
            val app = context.applicationContext
            val ringerMode = app.getSystemService(AudioManager::class.java)?.ringerMode
                ?: AudioManager.RINGER_MODE_NORMAL
            if (ringerMode == AudioManager.RINGER_MODE_SILENT) return
            if (ringerMode != AudioManager.RINGER_MODE_VIBRATE) {
                val tone = runCatching {
                    RingtoneManager.getRingtone(app, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                }.getOrNull()
                if (tone != null) {
                    // shortcut: ringtone looping needs API 28; older devices play once, vibration still repeats.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) tone.isLooping = true
                    runCatching { tone.play() }.onFailure { Log.w(TAG, "ringtone refused", it) }
                    ringtone = tone
                }
            }
            val vib = app.getSystemService(Vibrator::class.java) ?: return
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            runCatching {
                vib.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 1200, 800), 0), attrs)
            }.onFailure { Log.w(TAG, "vibration refused", it) }
            vibrator = vib
        }

        private fun stopRinging() {
            ringtone?.stop()
            ringtone = null
            vibrator?.cancel()
            vibrator = null
        }

        private fun handle(context: Context) =
            PhoneAccountHandle(ComponentName(context, DshConnectionService::class.java), ACCOUNT_ID)

        private fun telecom(context: Context) =
            context.applicationContext.getSystemService(TelecomManager::class.java)

        private fun showCallPage(context: Context, title: String, sessionId: String): PendingIntent? {
            val app = context.applicationContext
            appContext = app
            val manager = app.getSystemService(NotificationManager::class.java) ?: return null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(PAGE_CHANNEL) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(PAGE_CHANNEL, AppStrings.get(app, R.string.incoming_call_title), NotificationManager.IMPORTANCE_HIGH).apply {
                        setSound(null, null)
                        enableVibration(false)
                    },
                )
            }
            val options = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ActivityOptions.makeBasic().setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                ).toBundle()
            } else {
                null
            }
            val page = PendingIntent.getActivity(
                app, PAGE_ID,
                Intent(app, IncomingCallActivity::class.java)
                    .putExtra(IncomingCallService.EXTRA_TITLE, title)
                    .putExtra(IncomingCallService.EXTRA_SESSION, sessionId)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                options,
            )
            manager.notify(
                PAGE_ID,
                Notification.Builder(app, PAGE_CHANNEL)
                    .setSmallIcon(R.drawable.ic_stat_dsh)
                    .setContentTitle(AppStrings.get(app, R.string.incoming_call_title))
                    .setContentText(title)
                    .setContentIntent(page)
                    .setFullScreenIntent(page, true)
                    .setOngoing(true)
                    .build(),
            )
            return page
        }

        private fun cancelCallPage() {
            appContext?.getSystemService(NotificationManager::class.java)?.cancel(PAGE_ID)
        }

        internal fun register(context: Context) {
            val manager = telecom(context) ?: return
            val app = context.applicationContext
            val account = PhoneAccount.builder(handle(app), AppStrings.get(app, R.string.incoming_call_title))
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .setAddress(Uri.parse("dsh:incoming"))
                .setShortDescription(AppStrings.get(app, R.string.incoming_call_title))
                .setExtras(Bundle().apply {
                    putBoolean(PhoneAccount.EXTRA_ADD_SELF_MANAGED_CALLS_TO_INCALLSERVICE, false)
                })
                .build()
            runCatching { manager.registerPhoneAccount(account) }
                .onFailure { Log.w(TAG, "phone account registration refused", it) }
        }

        /** True only when Telecom accepted the call; no notification is involved. */
        fun alert(context: Context, title: String, sessionId: String): Boolean {
            val app = context.applicationContext
            val manager = telecom(app) ?: return false
            register(app)
            val extras = Bundle().apply {
                putString(IncomingCallService.EXTRA_TITLE, title)
                putString(IncomingCallService.EXTRA_SESSION, sessionId)
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle(app))
                putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, Uri.parse("dsh:$sessionId"))
                putBoolean(PhoneAccount.EXTRA_ADD_SELF_MANAGED_CALLS_TO_INCALLSERVICE, false)
            }
            return try {
                manager.addNewIncomingCall(handle(app), extras)
                true
            } catch (e: Exception) {
                Log.w(TAG, "Telecom refused the incoming call", e)
                false
            }
        }

        /** Dart answered: keep the connection up so the voice session outlives the ringing page. */
        fun answerFromDart() {
            val connection = active ?: return
            settled = true
            stopRinging()
            cancelCallPage()
            connection.setActive()
        }

        /** Dart dismissed or turned the switch off: end the telecom call without signalling back. */
        fun endFromDart() {
            val connection = active ?: return
            active = null
            settled = true
            stopRinging()
            cancelCallPage()
            connection.setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
            connection.destroy()
        }

        /** Whether the user still has to enable our calling account in the phone app's settings. */
        fun needsAccountEnable(context: Context): Boolean =
            telecom(context)?.getPhoneAccount(handle(context))?.isEnabled == false

        fun openAccountSettings(context: Context) {
            runCatching {
                context.startActivity(Intent(TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }.onFailure { Log.w(TAG, "could not open calling account settings", it) }
        }

        private fun signal(method: String) = IncomingCallPlugin.signal(method)
    }
}
