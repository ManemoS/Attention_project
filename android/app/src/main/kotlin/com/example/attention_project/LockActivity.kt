package com.example.attention_project

import android.animation.ObjectAnimator
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputFilter
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Full-screen cover shown over a locked app until the lock phase ends or the code is entered.
 *
 * Built in code rather than XML so it has no layout files to keep in sync. Its look matches the
 * Flutter app: deep ink, an amber countdown ring, Space Grotesk and Manrope (read from the
 * Flutter assets bundled in the APK).
 */
class LockActivity : Activity() {
    companion object {
        const val EXTRA_PACKAGE = "package"

        private const val INK = 0xFF0E1015.toInt()
        private const val INK_WARM = 0xFF1E170C.toInt()
        private const val CARD = 0xFF14171D.toInt()
        private const val CARD_BORDER = 0xFF262B35.toInt()
        private const val FIELD = 0xFF21252E.toInt()
        private const val TRACK = 0xFF21252E.toInt()
        private const val AMBER = 0xFFFFB547.toInt()
        private const val ON_AMBER = 0xFF2E1A00.toInt()
        private const val TEXT = 0xFFEDEEF2.toInt()
        private const val MUTED = 0xFFA2A8B5.toInt()
        private const val CORAL = 0xFFFF8070.toInt()
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var titleView: TextView
    private lateinit var countdownView: TextView
    private lateinit var ring: RingView
    private lateinit var card: LinearLayout
    private lateinit var codeInput: EditText
    private lateinit var errorView: TextView

    private val headingFace by lazy { font("SpaceGrotesk-700", Typeface.DEFAULT_BOLD) }
    private val bodyBold by lazy { font("Manrope-700", Typeface.DEFAULT_BOLD) }
    private val body by lazy { font("Manrope-500", Typeface.DEFAULT) }

    private val tick = object : Runnable {
        override fun run() {
            updateCountdown()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        drawBehindSystemBars()
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
        titleView.text = Lang.t(this, "${appLabel(pkg)} is locked", "${appLabel(pkg)} ถูกล็อกอยู่")
    }

    private fun updateCountdown() {
        val phase = LockState.currentPhase(this)
        if (phase == null || !phase.locked) {
            finish()
            return
        }
        countdownView.text = formatRemaining(phase.remainingMs)
        val total = LockState.lockMinutes(this) * 60_000f
        ring.progress = (phase.remainingMs / total).coerceIn(0f, 1f)
    }

    private fun tryCode() {
        if (LockState.stop(this, codeInput.text.toString())) {
            finish()
        } else {
            codeInput.text.clear()
            errorView.visibility = View.VISIBLE
            card.performHapticFeedback(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT
                else HapticFeedbackConstants.LONG_PRESS
            )
            ObjectAnimator.ofFloat(card, View.TRANSLATION_X, 0f, 18f, -18f, 12f, -12f, 6f, -6f, 0f)
                .setDuration(420)
                .start()
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
        if (pkg == null) return Lang.t(this, "This app", "แอปนี้")
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

    /** The app's fonts, from the Flutter assets. Falls back to the system font if one is missing. */
    private fun font(name: String, fallback: Typeface): Typeface =
        runCatching { Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/$name.ttf") }
            .getOrDefault(fallback)

    private fun dp(value: Int): Int = dpF(value.toFloat()).toInt()

    private fun dpF(value: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics)

    @Suppress("DEPRECATION")
    private fun drawBehindSystemBars() {
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
    }

    private fun rounded(color: Int, radiusDp: Float, strokeColor: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dpF(radiusDp)
        if (strokeColor != null) setStroke(dp(1), strokeColor)
    }

    private fun text(sizeSp: Float, color: Int, face: Typeface) = TextView(this).apply {
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        typeface = face
        gravity = Gravity.CENTER
    }

    private fun button(label: String, filled: Boolean, onClick: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        stateListAnimator = null
        typeface = bodyBold
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setTextColor(if (filled) ON_AMBER else MUTED)
        minHeight = dp(56)
        val shape = rounded(if (filled) AMBER else Color.TRANSPARENT, 18f)
        val ripple = if (filled) 0x33000000 else 0x22FFFFFF
        background = RippleDrawable(ColorStateList.valueOf(ripple), shape, rounded(Color.WHITE, 18f))
        setOnClickListener { onClick() }
    }

    private fun matchWidth(topMarginDp: Int) = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
    ).apply { topMargin = dp(topMarginDp) }

    private fun buildLayout(): View {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }

        val brand = text(12f, AMBER, bodyBold).apply {
            text = "APLS · FOCUS"
            letterSpacing = 0.24f
        }
        column.addView(brand, matchWidth(8))

        // The ring, with the countdown in the middle.
        val ringSize = minOf(dp(280), resources.displayMetrics.widthPixels - dp(64))
        val ringFrame = FrameLayout(this)
        ring = RingView(this)
        ringFrame.addView(ring, FrameLayout.LayoutParams(ringSize, ringSize))
        val center = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        center.addView(ImageView(this).apply { setImageResource(R.drawable.ic_lock_rounded) }, LinearLayout.LayoutParams(dp(34), dp(34)))
        countdownView = text(56f, TEXT, headingFace).apply {
            // Sized to the ring, so it fits on small phones too.
            setTextSize(TypedValue.COMPLEX_UNIT_PX, ringSize * 0.2f)
            fontFeatureSettings = "tnum"
            letterSpacing = -0.03f
            includeFontPadding = false
        }
        center.addView(countdownView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(6) })
        center.addView(text(14f, MUTED, body).apply { text = Lang.t(this@LockActivity, "until it opens again", "จนกว่าจะเปิดอีกครั้ง") })
        ringFrame.addView(center, FrameLayout.LayoutParams(ringSize, ringSize, Gravity.CENTER))
        column.addView(ringFrame, LinearLayout.LayoutParams(ringSize, ringSize).apply { topMargin = dp(20) })

        titleView = text(26f, TEXT, headingFace).apply { letterSpacing = -0.02f }
        column.addView(titleView, matchWidth(24))
        column.addView(
            text(15f, MUTED, body).apply {
                text = Lang.t(this@LockActivity, "Stay with it. It opens again when the timer ends.", "อดทนอีกนิด จะเปิดได้เมื่อหมดเวลา")
                setLineSpacing(0f, 1.2f)
            },
            matchWidth(8),
        )

        // The way out, for a timer set too long.
        card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(CARD, 24f, CARD_BORDER)
            setPadding(dp(20), dp(20), dp(20), dp(20))
        }
        card.addView(text(16f, TEXT, bodyBold).apply {
            text = Lang.t(this@LockActivity, "Set the timer too long?", "ตั้งเวลานานเกินไปเหรอ?")
            gravity = Gravity.START
        })
        card.addView(text(14f, MUTED, body).apply {
            text = Lang.t(this@LockActivity, "Enter your code to end the lock early.", "ใส่รหัสเพื่อปลดล็อกก่อนเวลา")
            gravity = Gravity.START
        }, matchWidth(4))
        codeInput = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            filters = arrayOf(InputFilter.LengthFilter(8))
            // Dots, not a word: the wide letter spacing meant for digits would spread a word out.
            hint = "••••"
            contentDescription = Lang.t(this@LockActivity, "Code", "รหัส")
            typeface = headingFace
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            letterSpacing = 0.3f
            fontFeatureSettings = "tnum"
            setTextColor(TEXT)
            setHintTextColor(0xFF5B606B.toInt())
            gravity = Gravity.CENTER
            background = rounded(FIELD, 16f)
            setPadding(dp(16), dp(14), dp(16), dp(14))
            imeOptions = EditorInfo.IME_ACTION_DONE
            setOnEditorActionListener { _, _, _ ->
                tryCode()
                true
            }
            setOnFocusChangeListener { _, _ -> errorView.visibility = View.GONE }
        }
        card.addView(codeInput, matchWidth(16))
        errorView = text(14f, CORAL, bodyBold).apply {
            text = Lang.t(this@LockActivity, "Wrong code. Try again.", "รหัสไม่ถูกต้อง ลองอีกครั้ง")
            visibility = View.GONE
        }
        card.addView(errorView, matchWidth(10))
        card.addView(button(Lang.t(this, "End lock with code", "ปลดล็อกด้วยรหัส"), filled = true) { tryCode() }, matchWidth(14))
        column.addView(card, matchWidth(28))

        column.addView(button(Lang.t(this, "Go to home screen", "กลับหน้าหลัก"), filled = false) { goHome() }, matchWidth(8))

        val scroll = ScrollView(this).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = false
            addView(column, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER,
            ))
        }

        return FrameLayout(this).apply {
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(INK_WARM, INK, INK))
            addView(scroll)
            // Keeps everything clear of the status bar, navigation bar and keyboard.
            setOnApplyWindowInsetsListener { view, insets ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                    view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
                } else {
                    @Suppress("DEPRECATION")
                    view.setPadding(
                        insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                        insets.systemWindowInsetRight, insets.systemWindowInsetBottom,
                    )
                }
                insets
            }
        }
    }

    /** An amber ring that empties as the lock runs out, with a soft glow and minute ticks. */
    private inner class RingView(context: Context) : View(context) {
        var progress = 1f
            set(value) {
                field = value
                invalidate()
            }

        private val stroke = dpF(14f)
        private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            color = TRACK
        }
        private val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            color = AMBER
        }
        private val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke * 1.6f
            strokeCap = Paint.Cap.ROUND
            color = (AMBER and 0x00FFFFFF) or (0x59 shl 24)
            maskFilter = BlurMaskFilter(dpF(12f), BlurMaskFilter.Blur.NORMAL)
        }
        private val tick = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeWidth = dpF(1.5f)
            strokeCap = Paint.Cap.ROUND
            color = CARD_BORDER
        }
        private val head = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xE6FFFFFF.toInt() }
        private val oval = RectF()

        init {
            // The blur needs software drawing.
            setLayerType(LAYER_TYPE_SOFTWARE, null)
        }

        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val radius = minOf(width, height) / 2f - stroke - dpF(12f)
            for (i in 0 until 60) {
                val angle = Math.toRadians(i * 6.0 - 90)
                val long = i % 5 == 0
                val inner = radius + stroke / 2 + dpF(4f)
                val outer = inner + dpF(if (long) 7f else 4f)
                canvas.drawLine(
                    cx + (inner * Math.cos(angle)).toFloat(), cy + (inner * Math.sin(angle)).toFloat(),
                    cx + (outer * Math.cos(angle)).toFloat(), cy + (outer * Math.sin(angle)).toFloat(),
                    tick,
                )
            }
            oval.set(cx - radius, cy - radius, cx + radius, cy + radius)
            canvas.drawCircle(cx, cy, radius, track)
            if (progress <= 0f) return
            val sweep = 360f * progress
            canvas.drawArc(oval, -90f, sweep, false, glow)
            canvas.drawArc(oval, -90f, sweep, false, arc)
            val end = Math.toRadians((-90f + sweep).toDouble())
            canvas.drawCircle(
                cx + (radius * Math.cos(end)).toFloat(), cy + (radius * Math.sin(end)).toFloat(),
                stroke / 5, head,
            )
        }
    }
}
