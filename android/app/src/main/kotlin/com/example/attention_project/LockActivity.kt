package com.example.attention_project

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/** Full-screen cover shown over a locked app until the lock phase ends or the code is entered. */
class LockActivity : Activity() {
    companion object {
        const val EXTRA_PACKAGE = "package"
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var titleView: TextView
    private lateinit var countdownView: TextView
    private lateinit var codeInput: EditText
    private lateinit var errorView: TextView

    private val tick = object : Runnable {
        override fun run() {
            updateCountdown()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildLayout())
        updateTitle()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        updateTitle()
    }

    override fun onResume() {
        super.onResume()
        handler.post(tick)
    }

    override fun onPause() {
        handler.removeCallbacks(tick)
        super.onPause()
    }

    @Deprecated("Back should leave the locked app, not return to it")
    override fun onBackPressed() {
        goHome()
    }

    private fun updateTitle() {
        val pkg = intent.getStringExtra(EXTRA_PACKAGE)
        titleView.text = "${appLabel(pkg)} is locked"
    }

    private fun updateCountdown() {
        val phase = LockState.currentPhase(this)
        if (phase == null || !phase.locked) {
            finish()
            return
        }
        countdownView.text = "Unlocks in ${formatRemaining(phase.remainingMs)}"
    }

    private fun tryCode() {
        if (LockState.stop(this, codeInput.text.toString())) {
            finish()
        } else {
            codeInput.text.clear()
            errorView.visibility = View.VISIBLE
        }
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }

    private fun appLabel(pkg: String?): String {
        if (pkg == null) return "This app"
        return try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            pkg
        }
    }

    private fun formatRemaining(ms: Long): String {
        val totalSeconds = (ms + 999) / 1000
        val h = totalSeconds / 3600
        val m = (totalSeconds % 3600) / 60
        val s = totalSeconds % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

    private fun buildLayout(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#121212"))
            setPadding(dp(32), dp(32), dp(32), dp(32))
        }

        fun text(sizeSp: Float, color: Int) = TextView(this).apply {
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
            gravity = Gravity.CENTER
        }

        val lockIcon = text(56f, Color.WHITE).apply { text = "🔒" }
        titleView = text(24f, Color.WHITE)
        countdownView = text(18f, Color.parseColor("#B0B0B0"))
        val hint = text(14f, Color.parseColor("#B0B0B0")).apply {
            text = "Set the timer too long? Enter your code to end the lock."
        }
        codeInput = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            this.hint = "Code"
            setTextColor(Color.WHITE)
            setHintTextColor(Color.GRAY)
            gravity = Gravity.CENTER
        }
        errorView = text(14f, Color.parseColor("#FF6B6B")).apply {
            text = "Wrong code"
            visibility = View.GONE
        }
        val unlockButton = Button(this).apply {
            text = "End lock with code"
            setOnClickListener { tryCode() }
        }
        val homeButton = Button(this).apply {
            text = "Go to home screen"
            setOnClickListener { goHome() }
        }

        val gap = dp(12)
        listOf(lockIcon, titleView, countdownView, hint, codeInput, errorView, unlockButton, homeButton)
            .forEach { view ->
                root.addView(
                    view,
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { topMargin = gap }
                )
            }
        return root
    }
}
