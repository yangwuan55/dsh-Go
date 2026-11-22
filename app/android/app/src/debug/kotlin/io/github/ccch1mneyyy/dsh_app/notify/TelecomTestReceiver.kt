package io.github.ccch1mneyyy.dsh_app.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/** Debug-only: raises the same ring a finished turn raises, through Dart. */
class TelecomTestReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "测试来电"
        val session = intent.getStringExtra("session") ?: "test-session"
        IncomingCallService.ensure(context, true)
        val engine = FlutterEngineCache.getInstance().get("dsh-main")
        if (engine == null) {
            DshConnectionService.alert(context, title, session)
            return
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, IncomingCallPlugin.CHANNEL)
            .invokeMethod("debugOffer", mapOf("title" to title, "sessionId" to session))
    }
}
