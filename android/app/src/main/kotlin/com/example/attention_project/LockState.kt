package com.example.attention_project

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The lock session, shared by the Flutter UI, the accessibility service and the lock screen.
 *
 * A session alternates between a locked phase and an unlocked phase. Which phase is active is
 * worked out from the start time, so nothing needs to be scheduled.
 *
 * Finished sessions and blocked app opens are kept too, for the Focus stats.
 */
object LockState {
    const val MAX_MINUTES = 120

    /**
     * Blocked as well during a strict session's locked time, so the lock can't be undone by
     * turning off Accessibility or uninstalling the app. The code still ends it.
     */
    val STRICT_PACKAGES = setOf(
        "com.android.settings",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
    )

    private const val PREFS = "app_lock_prefs"
    private const val KEY_ACTIVE = "active"
    private const val KEY_PACKAGES = "packages"
    private const val KEY_LOCK_MINUTES = "lockMinutes"
    private const val KEY_UNLOCK_MINUTES = "unlockMinutes"
    private const val KEY_START_LOCKED = "startLocked"
    private const val KEY_REPEAT = "repeat"
    private const val KEY_RECORD = "record"
    private const val KEY_STRICT = "strict"
    private const val KEY_START_MILLIS = "startMillis"
    private const val KEY_CODE_HASH = "codeHash"
    private const val KEY_HISTORY = "history"
    private const val KEY_BLOCKED = "blocked"

    /** Enough for a few months of daily sessions. */
    private const val MAX_HISTORY = 400

    /** Blocked-open counts are kept per day for this long. */
    private const val BLOCKED_DAYS = 60

    data class Phase(val locked: Boolean, val remainingMs: Long)

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun packages(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()

    fun lockMinutes(context: Context) = prefs(context).getInt(KEY_LOCK_MINUTES, 30)
    fun unlockMinutes(context: Context) = prefs(context).getInt(KEY_UNLOCK_MINUTES, 15)
    fun startLocked(context: Context) = prefs(context).getBoolean(KEY_START_LOCKED, true)
    fun repeat(context: Context) = prefs(context).getBoolean(KEY_REPEAT, true)
    fun record(context: Context) = prefs(context).getBoolean(KEY_RECORD, false)
    fun strict(context: Context) = prefs(context).getBoolean(KEY_STRICT, false)

    /** When the current (or most recent) session started. */
    fun startMillis(context: Context) = prefs(context).getLong(KEY_START_MILLIS, 0L)

    fun start(
        context: Context,
        packages: Set<String>,
        lockMinutes: Int,
        unlockMinutes: Int,
        startLocked: Boolean,
        repeat: Boolean,
        record: Boolean,
        code: String,
        strict: Boolean = false,
    ) = startWithHash(context, packages, lockMinutes, unlockMinutes, startLocked, repeat, record, hash(code), strict)

    /** Like [start], for callers that only keep the code's hash (the timetable). */
    fun startWithHash(
        context: Context,
        packages: Set<String>,
        lockMinutes: Int,
        unlockMinutes: Int,
        startLocked: Boolean,
        repeat: Boolean,
        record: Boolean,
        codeHash: String,
        strict: Boolean = false,
    ) {
        prefs(context).edit()
            .putStringSet(KEY_PACKAGES, HashSet(packages))
            .putInt(KEY_LOCK_MINUTES, lockMinutes.coerceIn(1, MAX_MINUTES))
            .putInt(KEY_UNLOCK_MINUTES, unlockMinutes.coerceIn(1, MAX_MINUTES))
            .putBoolean(KEY_START_LOCKED, startLocked)
            .putBoolean(KEY_REPEAT, repeat)
            .putBoolean(KEY_RECORD, record)
            .putBoolean(KEY_STRICT, strict)
            .putString(KEY_CODE_HASH, codeHash)
            .putLong(KEY_START_MILLIS, System.currentTimeMillis())
            .putBoolean(KEY_ACTIVE, true)
            .apply()
        FocusWidget.update(context)
    }

    /** Ends the session if [code] matches. Returns false for a wrong code. */
    fun stop(context: Context, code: String): Boolean {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ACTIVE, false)) return true
        if (hash(code) != p.getString(KEY_CODE_HASH, null)) return false
        end(context, System.currentTimeMillis())
        return true
    }

    fun isActive(context: Context) = prefs(context).getBoolean(KEY_ACTIVE, false)

    /** The current phase, or null when no session is running. */
    fun currentPhase(context: Context): Phase? {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ACTIVE, false)) return null

        val lockMs = lockMinutes(context) * 60_000L
        val unlockMs = unlockMinutes(context) * 60_000L
        val startLocked = startLocked(context)
        val firstMs = if (startLocked) lockMs else unlockMs
        val cycleMs = lockMs + unlockMs
        val elapsed = (System.currentTimeMillis() - p.getLong(KEY_START_MILLIS, 0L)).coerceAtLeast(0L)

        if (!repeat(context) && elapsed >= cycleMs) {
            end(context, p.getLong(KEY_START_MILLIS, 0L) + cycleMs)
            return null
        }

        val position = elapsed % cycleMs
        return if (position < firstMs) {
            Phase(startLocked, firstMs - position)
        } else {
            Phase(!startLocked, cycleMs - position)
        }
    }

    fun isPackageLocked(context: Context, packageName: String): Boolean {
        if (currentPhase(context)?.locked != true) return false
        return packageName in packages(context) || (strict(context) && packageName in STRICT_PACKAGES)
    }

    /** Ends the session as of [endMillis] and adds it to the history. */
    private fun end(context: Context, endMillis: Long) {
        val p = prefs(context)
        val session = JSONObject()
            .put("start", p.getLong(KEY_START_MILLIS, 0L))
            .put("end", endMillis)
            .put("lockMinutes", lockMinutes(context))
            .put("unlockMinutes", unlockMinutes(context))
            .put("startLocked", startLocked(context))
            .put("repeat", repeat(context))
        val history = history(context).put(session)
        while (history.length() > MAX_HISTORY) history.remove(0)
        p.edit()
            .putBoolean(KEY_ACTIVE, false)
            .remove(KEY_CODE_HASH)
            .putString(KEY_HISTORY, history.toString())
            .apply()
        FocusWidget.update(context)
    }

    /** Finished sessions, oldest first, as JSON objects. */
    fun history(context: Context): JSONArray =
        runCatching { JSONArray(prefs(context).getString(KEY_HISTORY, "[]")) }.getOrDefault(JSONArray())

    /** The running session so far, in the same shape as [history]'s entries, or null. */
    fun currentSession(context: Context): JSONObject? {
        if (currentPhase(context) == null) return null
        return JSONObject()
            .put("start", startMillis(context))
            .put("end", System.currentTimeMillis())
            .put("lockMinutes", lockMinutes(context))
            .put("unlockMinutes", unlockMinutes(context))
            .put("startLocked", startLocked(context))
            .put("repeat", repeat(context))
    }

    /** Counts one try at opening a locked app today. */
    fun recordBlocked(context: Context, packageName: String) {
        val p = prefs(context)
        val all = blocked(context)
        val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val counts = all.optJSONObject(day) ?: JSONObject()
        counts.put(packageName, counts.optInt(packageName) + 1)
        all.put(day, counts)
        // Days are ISO dates, so sorting them as strings sorts them by date.
        val days = all.keys().asSequence().toList().sorted()
        days.dropLast(BLOCKED_DAYS).forEach { all.remove(it) }
        p.edit().putString(KEY_BLOCKED, all.toString()).apply()
    }

    /** Replaces the focus history, for restoring a backup. */
    fun replaceHistory(context: Context, history: JSONArray, blocked: JSONObject) {
        prefs(context).edit()
            .putString(KEY_HISTORY, history.toString())
            .putString(KEY_BLOCKED, blocked.toString())
            .apply()
    }

    /** Blocked opens per day ("2026-11-06") and package. */
    fun blocked(context: Context): JSONObject =
        runCatching { JSONObject(prefs(context).getString(KEY_BLOCKED, "{}")) }.getOrDefault(JSONObject())

    private fun hash(code: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(code.toByteArray())
            .joinToString("") { "%02x".format(it) }
}
