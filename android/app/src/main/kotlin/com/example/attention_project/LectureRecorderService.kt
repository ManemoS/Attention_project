package com.example.attention_project

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.io.File

/**
 * Writes down what is said near the phone while a lock session runs.
 *
 * Android's speech recognizer stops after each pause, so this restarts it every time and appends
 * each finished sentence to lectures/<session start>.txt. It stops itself once the session ends.
 */
class LectureRecorderService : Service() {
    companion object {
        private const val CHANNEL_ID = "lecture_recording"
        private const val NOTIFICATION_ID = 1
        private const val SESSION_CHECK_MS = 5_000L

        @Volatile
        var isRunning = false
            private set

        fun lecturesDir(context: Context) = File(context.filesDir, "lectures").apply { mkdirs() }

        fun start(context: Context) {
            val intent = Intent(context, LectureRecorderService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LectureRecorderService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private lateinit var transcript: File

    /** Words heard so far in the current sentence, saved if the recognizer gives up mid-sentence. */
    private var partial = ""

    private val sessionCheck = object : Runnable {
        override fun run() {
            if (LockState.currentPhase(this@LectureRecorderService) == null) {
                stopSelf()
            } else {
                handler.postDelayed(this, SESSION_CHECK_MS)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (isRunning) return START_NOT_STICKY

        startInForeground()
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        isRunning = true
        transcript = File(lecturesDir(this), "${LockState.startMillis(this)}.txt")
        handler.post(sessionCheck)
        listen()
        // Not sticky: Android doesn't allow restarting a microphone service from the background.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (isRunning) savePartial()
        isRunning = false
        handler.removeCallbacksAndMessages(null)
        recognizer?.destroy()
        recognizer = null
        super.onDestroy()
    }

    private fun listen() {
        if (!isRunning) return
        val r = recognizer ?: SpeechRecognizer.createSpeechRecognizer(this).also {
            it.setRecognitionListener(listener)
            recognizer = it
        }
        r.startListening(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
        )
    }

    /** Starts listening again after [delayMs], with a fresh recognizer if the old one got stuck. */
    private fun restart(delayMs: Long, recreate: Boolean) {
        if (recreate) {
            recognizer?.destroy()
            recognizer = null
        }
        handler.postDelayed(::listen, delayMs)
    }

    private fun append(text: String) {
        if (text.isNotBlank()) transcript.appendText(text.trim() + "\n")
    }

    private fun savePartial() {
        append(partial)
        partial = ""
    }

    private val listener = object : RecognitionListener {
        override fun onResults(results: Bundle?) {
            val best = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
            if (best.isNullOrBlank()) savePartial() else append(best)
            partial = ""
            restart(0, recreate = false)
        }

        override fun onPartialResults(partialResults: Bundle?) {
            partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                ?.let { if (it.isNotBlank()) partial = it }
        }

        override fun onError(error: Int) {
            savePartial()
            when (error) {
                // Nobody spoke for a while: just listen again.
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> restart(0, recreate = false)

                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> stopSelf()

                // No internet or the speech service is down: wait a bit before trying again.
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                SpeechRecognizer.ERROR_SERVER -> restart(3_000, recreate = true)

                // Busy, or the microphone is taken (for example by a phone call).
                else -> restart(1_000, recreate = true)
            }
        }

        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun startInForeground() {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Lecture recording", NotificationManager.IMPORTANCE_LOW)
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Recording lecture")
            .setContentText("Writing down what's said until the lock session ends")
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
