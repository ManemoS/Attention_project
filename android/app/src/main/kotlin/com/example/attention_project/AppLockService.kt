package com.example.attention_project

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

/**
 * Watches which app is in the foreground and covers it with [LockActivity] while it is locked.
 *
 * Window events catch an app being opened. The once-a-second check catches a lock phase starting
 * while the user is already inside a locked app.
 */
class AppLockService : AccessibilityService() {
    companion object {
        /** Coming back to the same locked app within this long counts as the same try. */
        private const val SAME_TRY_MS = 15_000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var foregroundPackage: String? = null
    private var lastBlocked: String? = null
    private var lastBlockedAt = 0L

    /** The phase the widget last showed: null (no session), true (locked) or false (free). */
    private var widgetPhase: Boolean? = null

    private val poll = object : Runnable {
        override fun run() {
            rootInActiveWindow?.packageName?.toString()?.let { foregroundPackage = it }
            checkForeground()
            // The widget's countdown ticks by itself; it only needs redrawing when the phase flips.
            val phase = LockState.currentPhase(this@AppLockService)?.locked
            if (phase != widgetPhase) {
                widgetPhase = phase
                FocusWidget.update(this@AppLockService)
            }
            handler.postDelayed(this, 1000)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        handler.post(poll)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        foregroundPackage = event.packageName?.toString() ?: return
        checkForeground()
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        handler.removeCallbacks(poll)
        super.onDestroy()
    }

    private fun checkForeground() {
        val pkg = foregroundPackage ?: return
        if (pkg == packageName) return
        if (!LockState.isPackageLocked(this, pkg)) return

        val now = System.currentTimeMillis()
        if (pkg != lastBlocked || now - lastBlockedAt > SAME_TRY_MS) LockState.recordBlocked(this, pkg)
        lastBlocked = pkg
        lastBlockedAt = now

        startActivity(
            Intent(this, LockActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(LockActivity.EXTRA_PACKAGE, pkg)
        )
    }
}
