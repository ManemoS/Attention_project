package com.example.attention_project

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.speech.tts.TextToSpeech
import java.io.File
import java.util.Locale

/**
 * The voice side of "Ask your notes": records a spoken question (Whisper turns it into text on the
 * Flutter side) and reads answers aloud with the phone's text-to-speech.
 */
object QuestionVoice {
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pending: String? = null

    /** Starts recording a question. Returns false if the microphone is busy (say, with a lecture). */
    fun startRecording(context: Context): Boolean {
        stopRecording()
        val out = File(context.cacheDir, "question.m4a")
        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        return try {
            r.setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioChannels(1)
            r.setAudioSamplingRate(16_000)
            r.setAudioEncodingBitRate(32_000)
            r.setOutputFile(out.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            file = out
            true
        } catch (e: Exception) {
            r.release()
            false
        }
    }

    /** Stops recording and returns the file, or null if nothing usable was recorded. */
    fun stopRecording(): String? {
        val r = recorder ?: return null
        recorder = null
        val ok = runCatching { r.stop() }.isSuccess
        r.release()
        return if (ok) file?.absolutePath else null
    }

    fun speak(context: Context, text: String) {
        val engine = tts
        if (engine == null) {
            pending = text
            tts = TextToSpeech(context.applicationContext) { status ->
                ttsReady = status == TextToSpeech.SUCCESS
                if (ttsReady) {
                    tts?.language = Locale.US
                    pending?.let { say(it) }
                }
                pending = null
            }
        } else if (ttsReady) {
            say(text)
        }
    }

    private fun say(text: String) {
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "answer")
    }

    fun stopSpeaking() {
        tts?.stop()
    }
}
