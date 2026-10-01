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
    private val handler = Handler(Looper.getMainLooper())
    private var foregroundPackage: String? = null

    private val poll = object : Runnable {
        override fun run() {
            rootInActiveWindow?.packageName?.toString()?.let { foregroundPackage = it }
            checkForeground()
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

        startActivity(
            Intent(this, LockActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(LockActivity.EXTRA_PACKAGE, pkg)
        )
    }
}
