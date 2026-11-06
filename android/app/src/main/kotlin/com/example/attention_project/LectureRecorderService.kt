package com.example.attention_project

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Records the lecture as one continuous audio file while a lock session runs.
 *
 * The audio is turned into text after class, on the phone, with Whisper (see transcriber.dart).
 * That avoids the gaps live speech recognition leaves every time it restarts, and keeps a
 * recording to listen back to. Each recording is lectures/<start millis>.m4a, with a
 * lectures/<start millis>.json beside it for its bookmarks, length and course.
 */
class LectureRecorderService : Service() {
    companion object {
        private const val CHANNEL_ID = "lecture_recording"
        private const val NOTIFICATION_ID = 1
        private const val SESSION_CHECK_MS = 5_000L
        private const val ACTION_MARK = "com.example.attention_project.MARK"
        const val EXTRA_COURSE_PUBLIC = "course"

        /** Speech needs little: 16 kHz mono AAC at 32 kbps is about 15 MB an hour. */
        private const val SAMPLE_RATE = 16_000
        private const val BIT_RATE = 32_000

        @Volatile
        var isRunning = false
            private set

        /** The id (start time) of the recording in progress, or 0. */
        @Volatile
        var currentId = 0L
            private set

        /** Wall-clock time the recording started, for showing how long it has run. */
        @Volatile
        var startedAtMillis = 0L
            private set

        fun lecturesDir(context: Context) = File(context.filesDir, "lectures").apply { mkdirs() }

        /** Starts recording. [course] files the lecture into that folder (from the timetable). */
        fun start(context: Context, course: String? = null) {
            val intent = Intent(context, LectureRecorderService::class.java).putExtra(EXTRA_COURSE_PUBLIC, course)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LectureRecorderService::class.java))
        }

        /** Bookmarks this moment of the recording in progress. Returns false if nothing is recording. */
        fun mark(context: Context): Boolean {
            if (!isRunning) return false
            context.startService(Intent(context, LectureRecorderService::class.java).setAction(ACTION_MARK))
            return true
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recorder: MediaRecorder? = null
    private lateinit var metaFile: File
    private val marks = mutableListOf<Long>()
    private var course: String? = null

    /** Elapsed-time clock, so changing the phone's clock mid-lecture can't misplace bookmarks. */
    private var startedElapsed = 0L

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
        if (intent?.action == ACTION_MARK) {
            if (isRunning) addMark()
            return START_NOT_STICKY
        }
        if (isRunning) return START_NOT_STICKY

        startInForeground()
        course = intent?.getStringExtra(EXTRA_COURSE_PUBLIC)
        if (!startRecording()) {
            stopSelf()
            return START_NOT_STICKY
        }
        handler.post(sessionCheck)
        // Not sticky: Android doesn't allow restarting a microphone service from the background.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (isRunning) {
            runCatching { recorder?.stop() }
            writeMeta(finished = true)
        }
        recorder?.release()
        recorder = null
        isRunning = false
        currentId = 0L
        super.onDestroy()
    }

    private fun startRecording(): Boolean {
        val id = System.currentTimeMillis()
        val dir = lecturesDir(this)
        val audio = File(dir, "$id.m4a")
        metaFile = File(dir, "$id.json")
        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this) else @Suppress("DEPRECATION") MediaRecorder()
        return try {
            // MIC gets the phone's automatic gain, which lifts a lecturer speaking from the front
            // of the room more than the raw voice-recognition source does.
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioChannels(1)
            r.setAudioSamplingRate(SAMPLE_RATE)
            r.setAudioEncodingBitRate(BIT_RATE)
            r.setOutputFile(audio.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            currentId = id
            startedAtMillis = id
            startedElapsed = SystemClock.elapsedRealtime()
            isRunning = true
            writeMeta(finished = false)
            true
        } catch (e: Exception) {
            r.release()
            audio.delete()
            false
        }
    }

    private fun addMark() {
        marks.add(SystemClock.elapsedRealtime() - startedElapsed)
        writeMeta(finished = false)
        // Updates the notification so the tap visibly did something.
        startInForeground()
    }

    private fun writeMeta(finished: Boolean) {
        val json = JSONObject()
            .put("startedAt", currentId)
            .put("marks", JSONArray(marks))
            .put("recording", !finished)
        if (finished) json.put("durationMs", SystemClock.elapsedRealtime() - startedElapsed)
        course?.let { json.put("course", it) }
        runCatching { metaFile.writeText(json.toString()) }
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
        val markIntent = PendingIntent.getService(
            this, 1, Intent(this, LectureRecorderService::class.java).setAction(ACTION_MARK), PendingIntent.FLAG_IMMUTABLE
        )
        val markAction = Notification.Action.Builder(
            Icon.createWithResource(this, android.R.drawable.star_on), Lang.t(this, "Mark important", "มาร์กว่าสำคัญ"), markIntent,
        ).build()
        val text = when (marks.size) {
            0 -> Lang.t(this, "Tap Mark important at a key moment. Recording until the session ends.", "แตะมาร์กว่าสำคัญตอนช่วงสำคัญ อัดเสียงจนจบเซสชัน")
            1 -> Lang.t(this, "1 moment marked. Recording until the session ends.", "มาร์กไว้ 1 ช่วง อัดเสียงจนจบเซสชัน")
            else -> Lang.t(this, "${marks.size} moments marked. Recording until the session ends.", "มาร์กไว้ ${marks.size} ช่วง อัดเสียงจนจบเซสชัน")
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(Lang.t(this, "Recording lecture", "กำลังอัดเสียงการบรรยาย"))
            .setContentText(text)
            .setContentIntent(openApp)
            .addAction(markAction)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setUsesChronometer(true)
            .setWhen(if (startedAtMillis > 0) startedAtMillis else System.currentTimeMillis())
            .setShowWhen(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
