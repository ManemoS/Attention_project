package com.example.attention_project

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Calendar

/**
 * Starts a lock at each class on the user's weekly timetable, even when the app is closed.
 *
 * The Flutter side owns the timetable and sends a copy here with [save]. One alarm is set at a
 * time, for the next class; when it fires it locks the chosen apps for the length of the class,
 * offers to record the lecture, and sets the alarm for the class after.
 */
object Timetable {
    private const val PREFS = "timetable_prefs"
    private const val KEY_ENTRIES = "entries"
    private const val KEY_PACKAGES = "packages"
    private const val KEY_CODE_HASH = "codeHash"
    private const val KEY_STRICT = "strict"
    private const val KEY_ENABLED = "enabled"
    private const val CHANNEL_ID = "timetable"
    private const val NOTIFICATION_ID = 4
    const val EXTRA_COURSE = "course"
    const val EXTRA_END_MILLIS = "endMillis"
    const val EXTRA_RECORD = "record"

    /** One weekly class. [weekday] is 1 (Monday) to 7 (Sunday); times are minutes after midnight. */
    data class Entry(val weekday: Int, val start: Int, val end: Int, val course: String, val record: Boolean)

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Stores the timetable and schedules the next class. A blank [code] keeps the saved one. */
    fun save(context: Context, entries: String, packages: List<String>, code: String?, strict: Boolean, enabled: Boolean) {
        val edit = prefs(context).edit()
            .putString(KEY_ENTRIES, entries)
            .putStringSet(KEY_PACKAGES, packages.toSet())
            .putBoolean(KEY_STRICT, strict)
            .putBoolean(KEY_ENABLED, enabled)
        if (!code.isNullOrEmpty()) edit.putString(KEY_CODE_HASH, hash(code))
        edit.apply()
        schedule(context)
        FocusWidget.update(context)
    }

    fun hasCode(context: Context) = prefs(context).contains(KEY_CODE_HASH)

    fun canScheduleExact(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    private fun entries(context: Context): List<Entry> = runCatching {
        val array = JSONArray(prefs(context).getString(KEY_ENTRIES, "[]"))
        (0 until array.length()).map { i ->
            val o = array.getJSONObject(i)
            Entry(o.getInt("weekday"), o.getInt("start"), o.getInt("end"), o.getString("course"), o.optBoolean("record"))
        }
    }.getOrDefault(emptyList())

    /** When [entry] next starts, after [now]. */
    private fun nextStart(entry: Entry, now: Calendar): Calendar {
        val c = now.clone() as Calendar
        c.set(Calendar.HOUR_OF_DAY, entry.start / 60)
        c.set(Calendar.MINUTE, entry.start % 60)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        // Calendar counts Sunday as 1; the timetable counts Monday as 1.
        val today = (now.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
        var days = (entry.weekday - today + 7) % 7
        if (days == 0 && !c.after(now)) days = 7
        c.add(Calendar.DAY_OF_YEAR, days)
        return c
    }

    /** Sets one alarm, for the next class on the timetable, or none if it's off or empty. */
    fun schedule(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val pending = alarmIntent(context, null)
        alarms.cancel(pending)
        if (!prefs(context).getBoolean(KEY_ENABLED, false)) return

        val now = Calendar.getInstance()
        val next = entries(context).minByOrNull { nextStart(it, now).timeInMillis } ?: return
        val start = nextStart(next, now)
        val end = (start.clone() as Calendar).apply { add(Calendar.MINUTE, (next.end - next.start).coerceAtLeast(1)) }
        val intent = alarmIntent(context, next to end.timeInMillis)
        if (canScheduleExact(context)) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, start.timeInMillis, intent)
        } else {
            // Without the exact-alarm permission, Android may run this a few minutes late.
            alarms.setWindow(AlarmManager.RTC_WAKEUP, start.timeInMillis, 5 * 60_000L, intent)
        }
    }

    private fun alarmIntent(context: Context, next: Pair<Entry, Long>?): PendingIntent {
        val intent = Intent(context, TimetableReceiver::class.java)
        if (next != null) {
            intent.putExtra(EXTRA_COURSE, next.first.course)
                .putExtra(EXTRA_END_MILLIS, next.second)
                .putExtra(EXTRA_RECORD, next.first.record)
        }
        return PendingIntent.getBroadcast(
            context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** A class has started: lock the apps until it ends, unless a session is already running. */
    fun startClass(context: Context, course: String, endMillis: Long, record: Boolean) {
        val p = prefs(context)
        val codeHash = p.getString(KEY_CODE_HASH, null)
        val packages = p.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()
        val minutes = ((endMillis - System.currentTimeMillis()) / 60_000L).toInt()
        if (codeHash != null && packages.isNotEmpty() && minutes > 0 && !LockState.isActive(context)) {
            LockState.startWithHash(
                context,
                packages,
                lockMinutes = minutes,
                // A minute free at the end, then the session finishes by itself.
                unlockMinutes = 1,
                startLocked = true,
                repeat = false,
                record = false,
                codeHash = codeHash,
                strict = p.getBoolean(KEY_STRICT, false),
            )
            notifyStarted(context, course, endMillis, record)
        }
        schedule(context)
    }

    private fun notifyStarted(context: Context, course: String, endMillis: Long, record: Boolean) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Timetable", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "When a class on your timetable starts and locks your apps"
                }
            )
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val openApp = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val until = android.text.format.DateFormat.getTimeFormat(context).format(java.util.Date(endMillis))
        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentTitle(Lang.t(context, "$course has started", "$course เริ่มแล้ว"))
            .setContentText(Lang.t(context, "Your apps are locked until $until.", "แอปของคุณล็อกถึง $until"))
            .setContentIntent(openApp)
            .setAutoCancel(true)
        if (record) {
            val recordIntent = Intent(context, LectureRecorderService::class.java)
                .putExtra(LectureRecorderService.EXTRA_COURSE_PUBLIC, course)
            val start = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(context, 2, recordIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            } else {
                PendingIntent.getService(context, 2, recordIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }
            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(context, android.R.drawable.ic_btn_speak_now), Lang.t(context, "Record lecture", "อัดเสียงการบรรยาย"), start,
                ).build()
            )
        }
        runCatching { manager.notify(NOTIFICATION_ID, builder.build()) }
    }

    /** The next class, for the Flutter side to show, as {course, startMillis}. */
    fun next(context: Context): JSONObject? {
        if (!prefs(context).getBoolean(KEY_ENABLED, false)) return null
        val now = Calendar.getInstance()
        val next = entries(context).minByOrNull { nextStart(it, now).timeInMillis } ?: return null
        return JSONObject().put("course", next.course).put("startMillis", nextStart(next, now).timeInMillis)
    }

    private fun hash(code: String): String =
        MessageDigest.getInstance("SHA-256").digest(code.toByteArray()).joinToString("") { "%02x".format(it) }
}

/** Fires at the start of each timetabled class. */
class TimetableReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val course = intent.getStringExtra(Timetable.EXTRA_COURSE) ?: return Timetable.schedule(context)
        Timetable.startClass(
            context,
            course,
            intent.getLongExtra(Timetable.EXTRA_END_MILLIS, 0L),
            intent.getBooleanExtra(Timetable.EXTRA_RECORD, false),
        )
    }
}

/** Alarms are cleared when the phone restarts or the app updates, so set the next one again. */
class TimetableBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Timetable.schedule(context)
    }
}
