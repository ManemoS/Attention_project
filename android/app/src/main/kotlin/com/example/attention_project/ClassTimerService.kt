package com.example.attention_project

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator

/**
 * Vibrates when the current lesson segment's planned time runs out, even if the screen is off or
 * the professor has switched to their slides, and optionally once a little before. The Flutter side
 * owns the class state and calls [update] whenever the segment changes.
 *
 * Each buzz also posts a short alert notification, so a smartwatch paired with the phone buzzes on
 * the wrist too.
 */
class ClassTimerService : Service() {
    companion object {
        private const val CHANNEL_ID = "class_timer"
        private const val ALERT_CHANNEL_ID = "class_timer_alerts"
        private const val NOTIFICATION_ID = 2
        private const val ALERT_NOTIFICATION_ID = 3
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_DETAIL = "detail"
        private const val EXTRA_DUE_MILLIS = "dueMillis"
        private const val EXTRA_WARN_BEFORE_MILLIS = "warnBeforeMillis"

        /** Two short pulses: easy to feel in a hand or pocket, not loud on a desk. */
        private val BUZZ_PATTERN = longArrayOf(0, 120, 120, 120)

        /** One soft pulse for "time is nearly up". */
        private val WARN_PATTERN = longArrayOf(0, 90)

        /** Keeps the wake lock a little past the buzz in case the handler runs late. */
        private const val WAKE_LOCK_MARGIN_MS = 10_000L

        /** The alert only needs to reach the watch; it doesn't need to stay in the shade. */
        private const val ALERT_TIMEOUT_MS = 20_000L

        fun update(context: Context, title: String, detail: String, dueMillis: Long, warnBeforeMillis: Long = 0L) {
            val intent = Intent(context, ClassTimerService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_DETAIL, detail)
                .putExtra(EXTRA_DUE_MILLIS, dueMillis)
                .putExtra(EXTRA_WARN_BEFORE_MILLIS, warnBeforeMillis)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ClassTimerService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var segmentTitle = ""

    private val warn = Runnable {
        vibrate(WARN_PATTERN)
        alert(Lang.t(this, "2 minutes left", "เหลือ 2 นาที"), segmentTitle)
    }

    private val buzz = Runnable {
        vibrate(BUZZ_PATTERN)
        alert(Lang.t(this, "Time's up", "หมดเวลา"), segmentTitle)
        releaseWakeLock()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val dueMillis = intent?.getLongExtra(EXTRA_DUE_MILLIS, 0L) ?: 0L
        val warnBeforeMillis = intent?.getLongExtra(EXTRA_WARN_BEFORE_MILLIS, 0L) ?: 0L
        segmentTitle = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        startInForeground(segmentTitle, intent?.getStringExtra(EXTRA_DETAIL).orEmpty(), dueMillis)

        handler.removeCallbacks(warn)
        handler.removeCallbacks(buzz)
        releaseWakeLock()
        val delayMs = dueMillis - System.currentTimeMillis()
        if (delayMs > 0) {
            // The CPU only has to stay awake until the buzz, so a forgotten class can't drain the
            // battery: nothing runs once the segment's time is up.
            acquireWakeLock(delayMs + WAKE_LOCK_MARGIN_MS)
            handler.postDelayed(buzz, delayMs)
            if (warnBeforeMillis > 0 && delayMs > warnBeforeMillis) {
                handler.postDelayed(warn, delayMs - warnBeforeMillis)
            }
        }
        // Not sticky: the class state lives on the Flutter side, which restarts this when reopened.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(warn)
        handler.removeCallbacks(buzz)
        releaseWakeLock()
        getSystemService(NotificationManager::class.java).cancel(ALERT_NOTIFICATION_ID)
        super.onDestroy()
    }

    /** A brief heads-up notification, mainly so a paired watch buzzes on the wrist. */
    private fun alert(title: String, text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(ALERT_CHANNEL_ID, "Class timer alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "A short alert when a lesson segment is nearly over or over, for smartwatches"
                    // The phone already buzzes through the vibrator; this keeps it from buzzing twice.
                    enableVibration(false)
                    setSound(null, null)
                }
            )
            Notification.Builder(this, ALERT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) builder.setTimeoutAfter(ALERT_TIMEOUT_MS)
        runCatching { manager.notify(ALERT_NOTIFICATION_ID, builder.build()) }
    }

    private fun acquireWakeLock(timeoutMs: Long) {
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "attention_project:class_timer")
            .apply {
                setReferenceCounted(false)
                acquire(timeoutMs)
            }
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    private fun vibrate(pattern: LongArray) {
        @Suppress("DEPRECATION")
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        // Phones are usually on silent in class, and Android drops other kinds of vibration from
        // apps in the background. The alarm usage gets through in both cases.
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1), attributes)
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1, attributes)
        }
    }

    private fun startInForeground(title: String, detail: String, dueMillis: Long) {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Class timer", NotificationManager.IMPORTANCE_LOW)
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(detail)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setWhen(dueMillis)
            .setShowWhen(true)
            .setUsesChronometer(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) builder.setChronometerCountDown(true)
        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
