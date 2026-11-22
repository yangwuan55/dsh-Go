package io.github.ccch1mneyyy.dsh_app.notify

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.ccch1mneyyy.dsh_app.MainActivity

/** The Dart side of the full-screen call page. The call itself stays in Dart. */
class IncomingCallPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var context: Context? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        messenger = binding.binaryMessenger
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        messenger = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.error("no_context", "Incoming call plugin is not attached", null)
            return
        }
        when (call.method) {
            "prepare" -> {
                if (!IncomingCallService.ensure(ctx, true)) {
                    result.error("foreground_start_failed", "Android refused the foreground service", null)
                    return
                }
                DshConnectionService.register(ctx)
                if (DshConnectionService.needsAccountEnable(ctx)) DshConnectionService.openAccountSettings(ctx)
                requestCallPermissions()
                result.success(null)
            }
            "show" -> {
                val shown = DshConnectionService.alert(
                    ctx,
                    call.argument<String>("title").orEmpty(),
                    call.argument<String>("sessionId").orEmpty(),
                )
                if (shown) result.success(null)
                else result.error("call_show_failed", "Android refused the Telecom incoming call", null)
            }
            "answered" -> {
                DshConnectionService.answerFromDart()
                result.success(null)
            }
            "dismiss" -> {
                DshConnectionService.endFromDart()
                result.success(null)
            }
            "disable" -> {
                DshConnectionService.endFromDart()
                IncomingCallService.ensure(ctx, false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Missed-call notifications still come from Dart's notify channel. */
    private fun requestCallPermissions() {
        val activity = MainActivity.current?.get() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 8142)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val manager = context?.getSystemService(NotificationManager::class.java)
            if (manager?.canUseFullScreenIntent() == false) {
                val settings = Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:${activity.packageName}"),
                )
                runCatching { activity.startActivity(settings) }
            }
        }
    }

    companion object {
        const val CHANNEL = "dsh/incoming_call"
        private val main = Handler(Looper.getMainLooper())
        @Volatile private var messenger: BinaryMessenger? = null

        /** The native page's buttons/timeout, delivered to IncomingCallController. */
        fun signal(method: String) {
            val m = messenger ?: return
            main.post { MethodChannel(m, CHANNEL).invokeMethod(method, null) }
        }
    }
}
