package io.github.ccch1mneyyy.dsh_app.notify

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.github.ccch1mneyyy.dsh_app.MainActivity
import io.github.ccch1mneyyy.dsh_app.R
import io.github.ccch1mneyyy.dsh_app.i18n.AppStrings

/** The lock-screen call page. Every outcome goes back through Dart's controller. */
class IncomingCallActivity : Activity() {
    private val main = Handler(Looper.getMainLooper())
    private val timeout = Runnable { end("timeout") }
    private var settled = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (getSystemService(KeyguardManager::class.java) as? KeyguardManager)?.requestDismissKeyguard(this, null)
        }
        active = this
        setContentView(page(intent.getStringExtra(IncomingCallService.EXTRA_TITLE).orEmpty()))
        main.postDelayed(timeout, 60_000)
    }

    private fun page(title: String): LinearLayout {
        val ctx = AppStrings.context(this)
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#E6000000"))
            val pad = (24 * resources.displayMetrics.density).toInt()
            setPadding(pad, pad, pad, pad)
            addView(
                TextView(ctx).apply {
                    text = AppStrings.get(ctx, R.string.incoming_call_title)
                    textSize = 26f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                },
            )
            addView(
                TextView(ctx).apply {
                    text = title
                    textSize = 18f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                    setPadding(0, pad, 0, pad * 2)
                },
            )
            addView(
                Button(ctx).apply {
                    text = AppStrings.get(ctx, R.string.incoming_call_answer)
                    setOnClickListener { end("answer") }
                },
            )
            addView(
                Button(ctx).apply {
                    text = AppStrings.get(ctx, R.string.incoming_call_hangup)
                    setOnClickListener { end("hangup") }
                },
            )
        }
    }

    private fun end(signal: String) {
        if (settled) return
        settled = true
        main.removeCallbacks(timeout)
        IncomingCallPlugin.signal(signal)
        if (signal == "timeout") IncomingCallService.cancelAlert(this)
        if (signal == "answer") {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            )
        }
        finish()
    }

    override fun onDestroy() {
        main.removeCallbacks(timeout)
        if (!settled) IncomingCallPlugin.signal("hangup")
        if (active === this) active = null
        super.onDestroy()
    }

    companion object {
        @Volatile private var active: IncomingCallActivity? = null

        /** Dart hung up or turned the switch off: don't signal back into Dart. */
        fun finishFromDart() {
            active?.let { it.settled = true; it.finish() }
        }
    }
}
