package com.example.attention_project

import android.content.Context
import android.content.SharedPreferences
import java.security.MessageDigest

/**
 * The lock session, shared by the Flutter UI, the accessibility service and the lock screen.
 *
 * A session alternates between a locked phase and an unlocked phase. Which phase is active is
 * worked out from the start time, so nothing needs to be scheduled.
 */
object LockState {
    const val MAX_MINUTES = 120

    private const val PREFS = "app_lock_prefs"
    private const val KEY_ACTIVE = "active"
    private const val KEY_PACKAGES = "packages"
    private const val KEY_LOCK_MINUTES = "lockMinutes"
    private const val KEY_UNLOCK_MINUTES = "unlockMinutes"
    private const val KEY_START_LOCKED = "startLocked"
    private const val KEY_REPEAT = "repeat"
    private const val KEY_RECORD = "record"
    private const val KEY_START_MILLIS = "startMillis"
    private const val KEY_CODE_HASH = "codeHash"

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

    /** When the current (or most recent) session started. Also names its lecture transcript. */
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
    ) {
        prefs(context).edit()
            .putStringSet(KEY_PACKAGES, HashSet(packages))
            .putInt(KEY_LOCK_MINUTES, lockMinutes.coerceIn(1, MAX_MINUTES))
            .putInt(KEY_UNLOCK_MINUTES, unlockMinutes.coerceIn(1, MAX_MINUTES))
            .putBoolean(KEY_START_LOCKED, startLocked)
            .putBoolean(KEY_REPEAT, repeat)
            .putBoolean(KEY_RECORD, record)
            .putString(KEY_CODE_HASH, hash(code))
            .putLong(KEY_START_MILLIS, System.currentTimeMillis())
            .putBoolean(KEY_ACTIVE, true)
            .apply()
    }

    /** Ends the session if [code] matches. Returns false for a wrong code. */
    fun stop(context: Context, code: String): Boolean {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ACTIVE, false)) return true
        if (hash(code) != p.getString(KEY_CODE_HASH, null)) return false
        end(context)
        return true
    }

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
            end(context)
            return null
        }

        val position = elapsed % cycleMs
        return if (position < firstMs) {
            Phase(startLocked, firstMs - position)
        } else {
            Phase(!startLocked, cycleMs - position)
        }
    }

    fun isPackageLocked(context: Context, packageName: String): Boolean =
        currentPhase(context)?.locked == true && packageName in packages(context)

    private fun end(context: Context) {
        prefs(context).edit().putBoolean(KEY_ACTIVE, false).remove(KEY_CODE_HASH).apply()
    }

    private fun hash(code: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(code.toByteArray())
            .joinToString("") { "%02x".format(it) }
}
