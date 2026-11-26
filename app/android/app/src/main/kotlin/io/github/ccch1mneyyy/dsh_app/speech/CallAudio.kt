package io.github.ccch1mneyyy.dsh_app.speech

import android.media.AudioAttributes

/**
 * The stream the app's spoken audio rides on. A call puts both the microphone capture and her
 * voice on the voice-call stream, which is the stream the hardware volume keys adjust. Outside a
 * call she stays on the media stream like other app audio.
 */
object CallAudio {
    @Volatile var active = false

    fun attributes(contentType: Int = AudioAttributes.CONTENT_TYPE_SPEECH): AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(if (active) AudioAttributes.USAGE_VOICE_COMMUNICATION else AudioAttributes.USAGE_MEDIA)
            .setContentType(contentType)
            .build()
}
