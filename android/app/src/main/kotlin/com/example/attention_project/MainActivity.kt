package com.example.attention_project

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "attention_project/app_lock"
        private const val ICON_SIZE = 96
        private const val MIC_PERMISSION_REQUEST = 1
        private const val SAVE_BACKUP_REQUEST = 2
        private const val OPEN_BACKUP_REQUEST = 3
    }

    /** Waiting for the user to answer the microphone permission prompt. */
    private var micPermissionResult: MethodChannel.Result? = null

    /** Waiting for the user to pick where to save, or which backup to open. */
    private var pendingFileResult: MethodChannel.Result? = null
    private var pendingBackup: java.io.File? = null

    @Deprecated("Uses the platform activity result API, which FlutterActivity supports")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_BACKUP_REQUEST && requestCode != OPEN_BACKUP_REQUEST) return
        val result = pendingFileResult ?: return
        pendingFileResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            pendingBackup?.delete()
            result.success(if (requestCode == SAVE_BACKUP_REQUEST) false else null)
            return
        }
        Thread {
            try {
                if (requestCode == SAVE_BACKUP_REQUEST) {
                    Backup.saveTo(this, pendingBackup!!, uri)
                    runOnUiThread { result.success(true) }
                } else {
                    val settings = Backup.restore(this, uri)
                    runOnUiThread { result.success(settings) }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("backup", e.message, null) }
            }
        }.start()
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Re-sets the next class alarm in case it was lost (force-stop, an update, the clock changing).
        Timetable.schedule(this)
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

                "requestMicPermission" -> requestMicPermission(result)

                "getLecturesDir" -> result.success(LectureRecorderService.lecturesDir(this).absolutePath)

                "startSession" -> {
                    val packages = call.argument<List<String>>("packages").orEmpty()
                    val code = call.argument<String>("code").orEmpty()
                    val record = (call.argument<Boolean>("record") ?: false) && hasMicPermission()
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
                        record,
                        code,
                        call.argument<Boolean>("strict") ?: false,
                    )
                    if (record) LectureRecorderService.start(this)
                    result.success(null)
                }

                "getFocusHistory" -> result.success(
                    mapOf(
                        "sessions" to LockState.history(this)
                            .apply { LockState.currentSession(this@MainActivity)?.let { put(it) } }
                            .toString(),
                        "blocked" to LockState.blocked(this).toString(),
                        "names" to blockedAppNames(),
                    )
                )

                "stopSession" -> {
                    val stopped = LockState.stop(this, call.argument<String>("code").orEmpty())
                    if (stopped) LectureRecorderService.stop(this)
                    result.success(stopped)
                }

                "updateClassTimer" -> {
                    ClassTimerService.update(
                        this,
                        call.argument<String>("title").orEmpty(),
                        call.argument<String>("detail").orEmpty(),
                        // The channel sends small numbers as Int and large ones as Long.
                        call.argument<Number>("dueAtMillis")?.toLong() ?: 0L,
                        call.argument<Number>("warnBeforeMillis")?.toLong() ?: 0L,
                    )
                    result.success(null)
                }

                "markMoment" -> result.success(LectureRecorderService.mark(this))

                "refreshWidget" -> {
                    FocusWidget.update(this)
                    result.success(null)
                }

                "createBackup" -> {
                    val settings = call.argument<String>("settings") ?: "{}"
                    val includeAudio = call.argument<Boolean>("includeAudio") ?: false
                    val name = call.argument<String>("fileName") ?: "APLS backup.zip"
                    Thread {
                        try {
                            val zip = Backup.create(this, settings, includeAudio)
                            runOnUiThread {
                                pendingBackup = zip
                                pendingFileResult?.success(false)
                                pendingFileResult = result
                                startActivityForResult(
                                    Intent(Intent.ACTION_CREATE_DOCUMENT)
                                        .addCategory(Intent.CATEGORY_OPENABLE)
                                        .setType("application/zip")
                                        .putExtra(Intent.EXTRA_TITLE, name),
                                    SAVE_BACKUP_REQUEST,
                                )
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("backup", e.message, null) }
                        }
                    }.start()
                }

                "restoreBackup" -> {
                    pendingFileResult?.success(null)
                    pendingFileResult = result
                    startActivityForResult(
                        Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("*/*")
                            .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/octet-stream")),
                        OPEN_BACKUP_REQUEST,
                    )
                }

                "setTimetable" -> {
                    Timetable.save(
                        this,
                        call.argument<String>("entries") ?: "[]",
                        call.argument<List<String>>("packages").orEmpty(),
                        call.argument<String>("code"),
                        call.argument<Boolean>("strict") ?: false,
                        call.argument<Boolean>("enabled") ?: false,
                    )
                    result.success(null)
                }

                "getTimetableInfo" -> {
                    val next = Timetable.next(this)
                    result.success(
                        mapOf(
                            "hasCode" to Timetable.hasCode(this),
                            "exactAlarms" to Timetable.canScheduleExact(this),
                            "nextCourse" to next?.optString("course"),
                            "nextStartMillis" to next?.optLong("startMillis"),
                        )
                    )
                }

                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                                .setData(android.net.Uri.parse("package:$packageName"))
                        )
                    }
                    result.success(null)
                }

                "startQuestion" -> result.success(QuestionVoice.startRecording(this))

                "stopQuestion" -> result.success(QuestionVoice.stopRecording())

                "speak" -> {
                    QuestionVoice.speak(this, call.argument<String>("text").orEmpty())
                    result.success(null)
                }

                "stopSpeaking" -> {
                    QuestionVoice.stopSpeaking()
                    result.success(null)
                }

                "playerLoad" -> try {
                    result.success(LecturePlayer.load(call.argument<String>("path").orEmpty()))
                } catch (e: Exception) {
                    result.error("player", e.message, null)
                }

                "playerPlay" -> {
                    LecturePlayer.play()
                    result.success(null)
                }

                "playerPause" -> {
                    LecturePlayer.pause()
                    result.success(null)
                }

                "playerSeek" -> {
                    LecturePlayer.seekTo(call.argument<Int>("ms") ?: 0)
                    result.success(null)
                }

                "playerState" -> result.success(LecturePlayer.state())

                "playerRelease" -> {
                    LecturePlayer.release()
                    result.success(null)
                }

                "stopClassTimer" -> {
                    ClassTimerService.stop(this)
                    result.success(null)
                }

                "setKeepScreenOn" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }

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
            "record" to LockState.record(this),
            "strict" to LockState.strict(this),
            "recording" to LectureRecorderService.isRunning,
            "recordingStartedAt" to LectureRecorderService.startedAtMillis,
        )
    }

    /** Readable names for every app in the blocked-open counts. */
    private fun blockedAppNames(): Map<String, String> {
        val blocked = LockState.blocked(this)
        val packages = blocked.keys().asSequence()
            .flatMap { day -> blocked.getJSONObject(day).keys().asSequence() }
            .toSet()
        return packages.associateWith { appLabel(it) }
    }

    private fun hasMicPermission() =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun hasNotificationPermission() =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /**
     * Asks for the microphone and, on Android 13+, notifications (the "Recording" notice and the
     * timetable's "class has started"), whichever is still missing. Answers whether the mic is allowed.
     */
    private fun requestMicPermission(result: MethodChannel.Result) {
        val missing = buildList {
            if (!hasMicPermission()) add(Manifest.permission.RECORD_AUDIO)
            if (!hasNotificationPermission()) add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || missing.isEmpty()) {
            result.success(hasMicPermission())
            return
        }
        micPermissionResult?.success(false)
        micPermissionResult = result
        requestPermissions(missing.toTypedArray(), MIC_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != MIC_PERMISSION_REQUEST) return
        micPermissionResult?.success(hasMicPermission())
        micPermissionResult = null
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
