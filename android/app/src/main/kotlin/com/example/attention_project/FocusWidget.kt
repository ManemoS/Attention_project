package com.example.attention_project

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar

/**
 * The home-screen widget: the focus countdown while a session runs, otherwise the next class.
 *
 * The countdown is a Chronometer the launcher ticks by itself, so the widget only needs updating
 * when a phase starts or ends; LockState and AppLockService call [update] then.
 */
class FocusWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = update(context)

    companion object {
        private const val AMBER = 0xFFFFB547.toInt()
        private const val MINT = 0xFF62D6B2.toInt()

        fun update(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, FocusWidget::class.java))
            if (ids.isEmpty()) return
            val views = RemoteViews(context.packageName, R.layout.focus_widget)
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, open)

            val phase = LockState.currentPhase(context)
            if (phase != null) {
                val color = if (phase.locked) AMBER else MINT
                views.setTextViewText(R.id.widget_label, if (phase.locked) Lang.t(context, "LOCKED", "ล็อกอยู่") else Lang.t(context, "FREE TIME", "เวลาว่าง"))
                views.setTextColor(R.id.widget_label, color)
                views.setInt(R.id.widget_icon, "setColorFilter", color)
                views.setViewVisibility(R.id.widget_countdown, View.VISIBLE)
                views.setViewVisibility(R.id.widget_title, View.GONE)
                views.setChronometer(R.id.widget_countdown, SystemClock.elapsedRealtime() + phase.remainingMs, null, true)
                views.setChronometerCountDown(R.id.widget_countdown, true)
                views.setTextViewText(R.id.widget_detail, if (phase.locked) Lang.t(context, "until your apps open", "จนกว่าแอปจะเปิด") else Lang.t(context, "until your apps lock", "จนกว่าแอปจะล็อก"))
            } else {
                views.setTextViewText(R.id.widget_label, "APLS")
                views.setTextColor(R.id.widget_label, AMBER)
                views.setInt(R.id.widget_icon, "setColorFilter", AMBER)
                views.setChronometer(R.id.widget_countdown, SystemClock.elapsedRealtime(), null, false)
                views.setViewVisibility(R.id.widget_countdown, View.GONE)
                views.setViewVisibility(R.id.widget_title, View.VISIBLE)
                val next = Timetable.next(context)
                if (next != null) {
                    val start = Calendar.getInstance().apply { timeInMillis = next.getLong("startMillis") }
                    val day = start.getDisplayName(Calendar.DAY_OF_WEEK, Calendar.SHORT, java.util.Locale.getDefault())
                    val time = android.text.format.DateFormat.getTimeFormat(context).format(start.time)
                    views.setTextViewText(R.id.widget_title, next.getString("course"))
                    views.setTextViewText(R.id.widget_detail, Lang.t(context, "Next class · $day $time", "คลาสถัดไป · $day $time"))
                } else {
                    views.setTextViewText(R.id.widget_title, Lang.t(context, "Ready to focus", "พร้อมโฟกัส"))
                    views.setTextViewText(R.id.widget_detail, Lang.t(context, "Tap to start a session", "แตะเพื่อเริ่มเซสชัน"))
                }
            }
            manager.updateAppWidget(ids, views)
        }
    }
}
