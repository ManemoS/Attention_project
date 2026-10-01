package com.example.attention_project

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "attention_project/app_lock"
        private const val ICON_SIZE = 96
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> Thread {
                    val apps = installedApps()
                    runOnUiThread { result.success(apps) }
                }.start()

                "isAccessibilityEnabled" -> result.success(isAccessibilityEnabled())

                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }

                "getState" -> result.success(state())

                "startSession" -> {
                    val packages = call.argument<List<String>>("packages").orEmpty()
                    val code = call.argument<String>("code").orEmpty()
                    if (packages.isEmpty() || code.length < 4) {
                        result.error("invalid", "Choose at least one app and a code of 4+ digits", null)
                        return@setMethodCallHandler
                    }
                    LockState.start(
                        this,
                        packages.toSet(),
                        call.argument<Int>("lockMinutes") ?: 30,
                        call.argument<Int>("unlockMinutes") ?: 15,
                        call.argument<Boolean>("startLocked") ?: true,
                        call.argument<Boolean>("repeat") ?: true,
                        code,
                    )
                    result.success(null)
                }

                "stopSession" -> result.success(LockState.stop(this, call.argument<String>("code").orEmpty()))

                else -> result.notImplemented()
            }
        }
    }

    private fun state(): Map<String, Any> {
        val phase = LockState.currentPhase(this)
        return mapOf(
            "active" to (phase != null),
            "locked" to (phase?.locked ?: false),
            "remainingMs" to (phase?.remainingMs ?: 0L),
            "apps" to LockState.packages(this).map { mapOf("package" to it, "name" to appLabel(it)) },
            "lockMinutes" to LockState.lockMinutes(this),
            "unlockMinutes" to LockState.unlockMinutes(this),
            "startLocked" to LockState.startLocked(this),
            "repeat" to LockState.repeat(this),
        )
    }

    private fun installedApps(): List<Map<String, Any>> {
        val pm = packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcherIntent, 0)
            .distinctBy { it.activityInfo.packageName }
            .filter { it.activityInfo.packageName != packageName }
            .map {
                mapOf(
                    "package" to it.activityInfo.packageName,
                    "name" to it.loadLabel(pm).toString(),
                    "icon" to iconBytes(it.loadIcon(pm)),
                )
            }
            .sortedBy { (it["name"] as String).lowercase() }
    }

    private fun iconBytes(drawable: Drawable): ByteArray {
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun appLabel(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        pkg
    }

    private fun isAccessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            ?: return false
        val service = ComponentName(this, AppLockService::class.java)
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == service }
    }
}
