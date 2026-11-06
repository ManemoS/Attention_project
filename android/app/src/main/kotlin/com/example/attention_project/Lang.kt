package com.example.attention_project

import android.content.Context
import java.util.Locale

/**
 * The app language chosen in Flutter's Settings ("system", "en" or "th"), for the parts of the app
 * written natively: the lock screen, notifications and the home-screen widget.
 */
object Lang {
    fun isThai(context: Context): Boolean {
        val choice = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.app_language", "system")
        return choice == "th" || (choice == "system" && Locale.getDefault().language == "th")
    }

    /** [en], or [th] when the app is in Thai. */
    fun t(context: Context, en: String, th: String) = if (isThai(context)) th else en
}
